import SwiftUI
import AppKit
import NXLibraryCore

/// The Details page backdrop (Selene GameDetails: the hero art, the words'
/// side dark, a soft fade at the bottom). The hero sits on the right, faded
/// into the scrim on its left; the bottom gradient runs from clear at the top
/// to 0.93 of the scrim colour at 80 % of the height. Light palettes use the
/// palette's scrim; dark ones the Details navy (#0B1027). The Background
/// shade multiplies the gradient like Spotlight's shades.
struct DetailsBackground: View {
    @Environment(\.seleneCanvas) private var canvas

    let image: NSImage?
    /// Changes whenever `image` does; drives the crossfade.
    let imageKey: String
    /// Shown, blurred, while no hero is loaded (the app icon, as before).
    let fallback: NSImage
    var shade: BackgroundShade = .balanced

    /// The hero's share of the window width, on the right.
    private static let artWidth: CGFloat = 0.72

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                SeleneTheme.scrim
                Rectangle().fill(SeleneTheme.baseGradient).opacity(0.6)
                art(size: geo.size)
                leftFade
                bottomGradient
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var gradientColor: Color {
        ThemeStore.shared.palette.mode == .light ? SeleneTheme.scrim : Color(hex: 0x0B1027)
    }

    private func art(size: CGSize) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .id(imageKey)
                        .transition(.opacity)
                } else {
                    Image(nsImage: fallback)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: canvas.u(34))
                        .scaleEffect(1.2)
                }
            }
            .frame(width: size.width * Self.artWidth, height: size.height)
            .clipped()
            // A crossfade is not movement: it stays under reduce motion (spec §8).
            .animation(.easeInOut(duration: 0.4), value: imageKey)
        }
    }

    /// The words' side: dark behind the left column, clear by the middle.
    private var leftFade: some View {
        LinearGradient(stops: [
            .init(color: gradientColor.opacity(0.9), location: 0),
            .init(color: gradientColor.opacity(0.75), location: 0.3),
            .init(color: gradientColor.opacity(0), location: 0.6)
        ], startPoint: .leading, endPoint: .trailing)
    }

    /// Clear at the top, 0.93 of the colour at 80 % of the height and below (Selene's GameDetailsBackgroundBrush).
    private var bottomGradient: some View {
        let peak = min(1, 0.93 * shade.scrimMultiplier)
        return LinearGradient(stops: [
            .init(color: gradientColor.opacity(0), location: 0),
            .init(color: gradientColor.opacity(peak), location: 0.8),
            .init(color: gradientColor.opacity(peak), location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }
}
