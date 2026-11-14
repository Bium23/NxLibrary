import AppKit
import SwiftUI

/// Valve's Steam logo, the inverse (white) artwork from the Steam brand guidelines, unaltered: it stands alone,
/// with its ® mark, at least 50 pixels tall on screen and with clear space around it of the locomotive crank's
/// diameter (the symbol's larger ring, about a third of the logo's height). Valve's attribution is in NOTICE and
/// in Settings › About. Without the artwork in the bundle the platform is written out instead.
struct SteamPlatformLogo: View {
    static let platformName = "Steam"
    /// The guidelines' on-screen minimum, in pixels.
    static let minimumPixels: CGFloat = 50
    /// The crank ring's diameter as a share of the logo's height.
    static let clearSpaceRatio: CGFloat = 1.0 / 3

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
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: Self.platformName))
    }
}
