import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import NXLibraryCore

/// A tile of the grid: its preview, its caption and whether it is the current art.
extension ChangeArtworkView {
    // MARK: - Tiles

    func tileView(_ tile: Tile, focused: Bool) -> some View {
        let size = CGSize(width: canvas.u(tileSize.width), height: canvas.u(tileSize.height))
        let radius = canvas.u(12)
        let face = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return VStack(alignment: .leading, spacing: canvas.u(8)) {
            ZStack(alignment: .topTrailing) {
                face.fill(SeleneTheme.glass)
                preview(tile, size: size)
                    .frame(width: size.width, height: size.height)
                    .clipShape(face)
                if isCurrent(tile) {
                    MaterialIconView(.check, size: 26)
                        .foregroundColor(SeleneTheme.focus)
                        .padding(canvas.u(4))
                        .background(Circle().fill(SeleneTheme.glassSolid))
                        .padding(canvas.u(8))
                }
            }
            .frame(width: size.width, height: size.height)
            // The ring sits 6 outside the tile, centred on it.
            .overlay(SeleneTileRing(cornerRadius: canvas.u(18), active: focused).padding(canvas.u(-6)))
            VStack(alignment: .leading, spacing: canvas.u(2)) {
                Text(caption(tile).title)
                    .seleneFont(14, .semibold)
                    .foregroundColor(SeleneTheme.ink)
                Text(caption(tile).detail)
                    .seleneFont(13)
                    .foregroundColor(SeleneTheme.ink60)
            }
            .lineLimit(1)
            .frame(width: size.width, alignment: .leading)
        }
        .scaleEffect(focused ? 1.04 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: focused)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption(tile).title), \(caption(tile).detail)")
        .accessibilityAddTraits(isCurrent(tile) ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func preview(_ tile: Tile, size: CGSize) -> some View {
        switch tile {
        case .automatic:
            if slot == .icon, let automaticIconPreview { image(automaticIconPreview) }
            else { glyphFace(.restore) }
        case .iconLocation:
            glyphFace(.settings)
        case .file:
            glyphFace(.folder)
        case .browse:
            glyphFace(.language)
        case .yourPick:
            if let pickPreview { image(pickPreview) } else { glyphFace(.image) }
        case .art(let item):
            image(item.preview)
        }
    }

    /// Logos fit on the glass so their edges show; everything else fills the tile.
    func image(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: fits(image) ? .fit : .fill)
            .padding(slot == .logo ? canvas.u(18) : 0)
    }

    /// Logos, and banners much wider than the tile (Steam's library hero), show whole instead of cropped.
    private func fits(_ image: NSImage) -> Bool {
        slot == .logo || (slot == .background && image.size.width > image.size.height * 2.2)
    }

        private func glyphFace(_ icon: MaterialIcon) -> some View {
        MaterialIconView(icon, size: 44)
            .foregroundColor(SeleneTheme.ink60)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func caption(_ tile: Tile) -> (title: String, detail: String) {
        switch tile {
        case .automatic:
            switch slot {
            case _ where subject.steam != nil: return (L10n.text("Automatic"), steamAutomatic)
            case .cover: return (L10n.text("Automatic"), L10n.text("GameTDB, or a composed cover"))
            case .background: return (L10n.text("Automatic"), L10n.text("The game's own art, then Title DB"))
            case .icon: return (L10n.text("Automatic"), L10n.text("The game's own icon, then Title DB"))
            case .logo: return (L10n.text("Automatic"), L10n.text("The store logo, then Steam"))
            }
        case .yourPick:
            return (L10n.text("Your pick"), L10n.text("Saved on this Mac"))
        case .iconLocation:
            return (L10n.text("Icon location"), macApp.map(appIcon.usesIconOnMac) == true ? L10n.text("Use on the Mac") : "Only here")
        case .art(let item):
            return (item.art.candidate.source, item.art.resolution)
        case .browse(let source):
            let keyless = source.needsKey && !viewModel.hasSteamGridDBKey
            return (source.title, keyless ? L10n.text("Browse online · add your key") : "Browse online")
        case .file:
            return (L10n.text("From file…"), L10n.text("PNG or JPEG"))
        }
    }

    /// What Automatic shows for a Steam game in this tab.
    private var steamAutomatic: String {
        switch slot {
        case .cover: return L10n.text("Steam’s library cover")
        case .background: return L10n.text("Screen-shaped art, then Steam")
        case .icon: return L10n.text("The Mac app’s own icon")
        case .logo: return L10n.text("Steam’s logo")
        }
    }

    private func isCurrent(_ tile: Tile) -> Bool {
        switch tile {
        case .automatic: return !hasPick
        case .yourPick: return true
        default: return false
        }
    }
}
