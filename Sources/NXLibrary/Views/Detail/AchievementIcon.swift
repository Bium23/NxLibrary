import SwiftUI
import AppKit
import NXLibraryCore

/// An achievement's icon from Steam's CDN, cached by `SteamMetadataService.achievementIcon`. A neutral square
/// stands in until it arrives, and stays when it cannot be loaded (offline, unknown file).
struct AchievementIcon: View {
    @Environment(\.seleneCanvas) private var canvas

    let appID: UInt32
    let file: String?
    /// Canvas units.
    let size: CGFloat
    /// Locked: Steam's gray icon, dimmed a little more on the page.
    var dimmed = false

    @State private var image: NSImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: canvas.u(size * 0.16), style: .continuous)
        ZStack {
            shape.fill(SeleneTheme.ink15)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            }
        }
        .frame(width: canvas.u(size), height: canvas.u(size))
        .clipShape(shape)
        .opacity(dimmed ? 0.5 : 1)
        .accessibilityHidden(true)
        .task(id: file) {
            image = nil
            guard let file, let url = await SteamMetadataService.shared.achievementIcon(appID: appID, file: file),
                  !Task.isCancelled else { return }
            // Read and decoded off the main thread; at most 2 MiB, already validated as an image.
            let loaded = await Task.detached(priority: .utility) { NSImage(contentsOf: url) }.value
            guard !Task.isCancelled else { return }
            withAnimation(SeleneTheme.quick) { image = loaded }
        }
    }
}
