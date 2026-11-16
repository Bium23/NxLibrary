import SwiftUI
import AppKit
import NXLibraryCore

/// A tier's crystal (Arcane, Gold, Silver, Bronze), from the prerendered art in Core's resources. Dimmed:
/// a tier not earned yet, or a locked achievement's tier — gray and faint, so the lit ones read first.
/// Draws nothing if the art is missing.
struct TierCrystal: View {
    @Environment(\.seleneCanvas) private var canvas

    let tier: AchievementTier
    /// The square the art fills, in canvas units; the crystal is about half as wide as it is tall.
    let size: CGFloat
    var dimmed = false

    var body: some View {
        Group {
            if let image = Self.image(tier) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    // Not earned: a trace of its colour, so gold, silver and bronze still tell apart (in black and
                    // white the three read alike; maintainer's choice, 16 Nov 2026).
                    .saturation(dimmed ? 0.35 : 1)
                    .opacity(dimmed ? 0.55 : 1)
            } else {
                Color.clear
            }
        }
        .frame(width: canvas.u(size), height: canvas.u(size))
        .accessibilityHidden(true)
    }

    /// Four small PNGs, decoded once and kept for the app's life.
    @MainActor private static var cache: [AchievementTier: NSImage] = [:]

    @MainActor private static func image(_ tier: AchievementTier) -> NSImage? {
        if let image = cache[tier] { return image }
        guard let url = tier.imageURL, let image = NSImage(contentsOf: url) else { return nil }
        cache[tier] = image
        return image
    }
}
