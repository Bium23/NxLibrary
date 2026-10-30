import SwiftUI
import AppKit
import NXLibraryCore

/// Selene's full-bleed backdrop (Main.xaml SeleneHubGameBackground): the backdrop
/// (base gradient, wallpaper, ambient motion), the selected game's art
/// crossfading on change, and the left, bottom and top shades at 0.3 scaled by
/// the Background shade setting. Shared by Spotlight and Collection.
struct SeleneArtBackground: View {
    let image: NSImage?
    /// Changes whenever `image` does; drives the crossfade.
    let imageKey: String
    var shade: BackgroundShade = .balanced
    /// Crossfade length; Collection takes a slower one so the art turns after the logo.
    var crossfade: Double = 0.4
    /// Spotlight's backdrop by default; Collection passes `.library`.
    var backdrop = SeleneBackdrop.home

    var body: some View {
        ZStack {
            // Under a game's art the moonlight is hidden: it holds still (Selene fades it out there).
            backdrop.still(image != nil)
            ZStack {
                if let image {
                    Color.clear
                        .overlay(
                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fill)
                        )
                        .clipped()
                        .id(imageKey)
                        .transition(.opacity)
                }
            }
            // A crossfade is not movement: it stays under reduce motion (spec §8).
            .animation(.easeInOut(duration: crossfade), value: imageKey)
            shades
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var shades: some View {
        let k = 0.3 * shade.scrimMultiplier
        return ZStack {
            Rectangle().fill(LinearGradient(stops: [
                stop(0.878, k, at: 0), stop(0.5, k, at: 0.5), stop(0.149, k, at: 1)
            ], startPoint: .leading, endPoint: .trailing))
            Rectangle().fill(LinearGradient(stops: [
                stop(0, k, at: 0.4), stop(0.9, k, at: 1)
            ], startPoint: .top, endPoint: .bottom))
            Rectangle().fill(LinearGradient(stops: [
                stop(0.9, k, at: 0), stop(0.44, k, at: 0.1), stop(0, k, at: 0.26)
            ], startPoint: .top, endPoint: .bottom))
        }
    }

    /// A scrim stop: Selene's opacity-mask alpha times the shade's opacity.
    private func stop(_ mask: Double, _ opacity: Double, at location: CGFloat) -> Gradient.Stop {
        .init(color: SeleneTheme.scrim.opacity(min(1, mask * opacity)), location: location)
    }
}
