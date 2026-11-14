import AppKit
import SwiftUI

/// Valve's Steam logo, the inverse (white) artwork from the Steam brand guidelines, unaltered: it stands alone,
/// with its ® mark, at least 50 pixels tall on screen; the caller leaves clear space around it of the locomotive
/// crank's diameter (the symbol's larger ring, about a third of the logo's height). Valve's attribution is in
/// NOTICE and in Settings › About. Without the artwork in the bundle the platform is written out instead, as a
/// stat value.
struct SteamPlatformLogo: View {
    static let platformName = "Steam"
    /// The guidelines' on-screen minimum, in pixels.
    static let minimumPixels: CGFloat = 50

    @Environment(\.displayScale) private var displayScale

    /// The height asked for, raised to the on-screen minimum on this display.
    let height: CGFloat

    static func height(_ wanted: CGFloat, displayScale: CGFloat) -> CGFloat {
        max(wanted, minimumPixels / max(displayScale, 1))
    }

    private static let artwork: NSImage? = Bundle.main.url(forResource: "SteamLogo", withExtension: "png",
                                                           subdirectory: "Brands").flatMap(NSImage.init(contentsOf:))

    var body: some View {
        Group {
            if let artwork = Self.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: Self.height(height, displayScale: displayScale))
            } else {
                Text(Self.platformName)
                    .seleneFont(21, .semibold)
                    .foregroundColor(SeleneTheme.ink)
            }
        }
    }
}
