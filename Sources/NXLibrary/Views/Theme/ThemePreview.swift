import SwiftUI
import AppKit
import NXLibraryCore

/// The Theme screen's preview (Selene's ProfileSteps.Preview): a small home in
/// a palette that need not be active yet, over its wallpaper or, without one,
/// its own moonlight backdrop. Tiles show the library's own square art.
struct ThemePreview: View {
    @Environment(\.seleneCanvas) private var canvas
    let palette: SelenePalette
    let wallpaperURL: URL?
    let games: [PortedGame]
    /// Width in Selene units; 16:9.
    let width: CGFloat

    @State private var art: [NSImage] = []

    var body: some View {
        let w = canvas.u(width)
        let h = w * 9 / 16
        let shape = RoundedRectangle(cornerRadius: canvas.u(16), style: .continuous)
        return VStack(alignment: .leading, spacing: canvas.u(10)) {
            Text("PREVIEW")
                .seleneFont(13, .semibold)
                .foregroundColor(SeleneTheme.ink.opacity(0.55))
                .padding(.leading, canvas.u(2))
            ZStack(alignment: .topLeading) {
                Rectangle().fill(SeleneTheme.baseGradient(for: palette))
                if let wallpaperURL {
                    WallpaperThumb(url: wallpaperURL).opacity(0.6)
                } else {
                    MoonlightBackdrop(accent: Color(hex: palette.glyph), ink: Color(hex: palette.ink),
                                      moving: false, asImage: true)
                }
                scrims
                home(w: w, h: h)
            }
            .frame(width: w, height: h)
            .clipShape(shape)
            .overlay(shape.strokeBorder(SeleneTheme.ink25, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: canvas.u(20))
            .animation(.easeOut(duration: 0.25), value: palette.id)
            .animation(.easeOut(duration: 0.25), value: wallpaperURL)
        }
        .task(id: games.map(\.id)) {
            art = games.prefix(6).map { GameIconProvider.squareArt(for: $0) ?? GameIconProvider.icon(for: $0) }
        }
        .accessibilityHidden(true)
    }

    private var scrims: some View {
        let scrim = Color(hex: palette.scrim)
        return ZStack {
            LinearGradient(stops: [.init(color: scrim.opacity(0.8), location: 0),
                                   .init(color: scrim.opacity(0.45), location: 0.5),
                                   .init(color: scrim.opacity(0.1), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [.init(color: scrim.opacity(0.75), location: 0),
                                   .init(color: scrim.opacity(0), location: 0.26)],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(stops: [.init(color: scrim.opacity(0), location: 0.55),
                                   .init(color: scrim.opacity(0.8), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private func home(w: CGFloat, h: CGFloat) -> some View {
        let ink = Color(hex: palette.ink)
        let focus = Color(hex: palette.focus)
        let glass = Color(hex: palette.glass, opacity: 0.72)
        let tile = w * 0.085
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: w * 0.02) {
                Text("Spotlight").foregroundColor(ink)
                Text("Collection").foregroundColor(ink.opacity(0.6))
            }
            .font(.system(size: w * 0.018, weight: .semibold))
            HStack(spacing: w * 0.016) {
                ForEach(0..<6, id: \.self) { index in
                    ZStack {
                        glass
                        if index < art.count {
                            Image(nsImage: art[index]).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                        }
                    }
                    .frame(width: tile, height: tile)
                    .clipShape(RoundedRectangle(cornerRadius: tile * 0.14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: tile * 0.2, style: .continuous)
                            .strokeBorder(focus, lineWidth: max(1, w * 0.003))
                            .padding(-w * 0.005)
                            .opacity(index == 0 ? 1 : 0))
                    .scaleEffect(index == 0 ? 1.3 : 1, anchor: .leading)
                    .padding(.trailing, index == 0 ? tile * 0.3 : 0)
                }
            }
            .padding(.top, h * 0.12)
            Text(games.first?.name ?? "Your games")
                .font(.system(size: w * 0.034, weight: .semibold))
                .foregroundColor(ink)
                .lineLimit(1)
                .padding(.top, h * 0.2)
            HStack(spacing: w * 0.012) {
                Text("Play")
                    .foregroundColor(Color(hex: palette.onFocus))
                    .padding(.horizontal, w * 0.04)
                    .padding(.vertical, w * 0.01)
                    .background(Capsule().fill(focus))
                Text("Details")
                    .foregroundColor(ink)
                    .padding(.horizontal, w * 0.032)
                    .padding(.vertical, w * 0.01)
                    .background(Capsule().fill(glass))
                    .overlay(Capsule().strokeBorder(ink.opacity(0.22), lineWidth: 1))
            }
            .font(.system(size: w * 0.02, weight: .semibold))
            .padding(.top, h * 0.04)
        }
        .padding(.leading, w * 0.045)
        .padding(.top, w * 0.035)
    }
}
