import SwiftUI
import AppKit
import NXLibraryCore

/// The Details page backdrop (Selene GameDetails.xaml): the hero art on the
/// right, then three scrims in the palette's scrim colour, each an opacity
/// mask: the words' side (0.95 at the left edge, 0.70 at the middle, 0.15 at
/// the right), the bottom (clear to 40 % of the height, 0.90 at the foot) and
/// a radial vignette (clear to 60 % of the radius, 0.55 at the edge). The
/// Background shade multiplies each mask like Spotlight's shades.
struct DetailsBackground: View {
    let image: NSImage?
    /// Changes whenever `image` does; drives the crossfade.
    let imageKey: String
    /// Shown, blurred, while no hero is loaded (the app icon, as before).
    let fallback: NSImage
    var shade: BackgroundShade = .balanced

    @Environment(\.seleneCanvas) private var canvas

    /// The hero's share of the window width, on the right.
    private static let artWidth: CGFloat = 0.72

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                SeleneTheme.scrim
                Rectangle().fill(SeleneTheme.baseGradient).opacity(0.6)
                art(size: geo.size)
                // GameDetails.xaml's three Borders, in order.
                Rectangle().fill(SeleneTheme.scrim).mask(sideMask)
                Rectangle().fill(SeleneTheme.scrim).mask(bottomMask)
                Rectangle().fill(SeleneTheme.scrim).mask(vignetteMask(size: geo.size))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

    /// The Background shade's multiplier on an alpha, capped at 1.
    private func alpha(_ value: Double) -> Double {
        min(1, value * shade.scrimMultiplier)
    }

    private var sideMask: LinearGradient {
        LinearGradient(stops: [
            .init(color: .black.opacity(alpha(0.95)), location: 0),
            .init(color: .black.opacity(alpha(0.70)), location: 0.5),
            .init(color: .black.opacity(alpha(0.15)), location: 1)
        ], startPoint: .leading, endPoint: .trailing)
    }

    private var bottomMask: LinearGradient {
        LinearGradient(stops: [
            .init(color: .black.opacity(0), location: 0.4),
            .init(color: .black.opacity(alpha(0.90)), location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }

    /// An ellipse with radii 0.8 × width and 0.9 × height (Selene's RadiusX / RadiusY),
    /// built as a circle scaled vertically so the stops land on the ellipse.
    private func vignetteMask(size: CGSize) -> some View {
        let rx = size.width * 0.8
        let ry = size.height * 0.9
        return RadialGradient(stops: [
            .init(color: .black.opacity(0), location: 0.6),
            .init(color: .black.opacity(alpha(0.55)), location: 1)
        ], center: .center, startRadius: 0, endRadius: max(rx, 1))
            .frame(width: rx * 2, height: rx * 2)
            .scaleEffect(x: 1, y: rx > 0 ? ry / rx : 1, anchor: .center)
            .frame(width: size.width, height: size.height)
    }
}
