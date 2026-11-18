import SwiftUI
import AppKit
import NXLibraryCore

/// An achievement's icon from Steam's CDN, cached by `SteamMetadataService.achievementIcon`. A neutral square
/// stands in until it arrives, and stays when it cannot be loaded (offline, unknown file).
/// Decoded icons are kept in memory: the Achievements list draws only the rows near the window and makes them
/// again as they scroll back, and each came back as the grey square fading to its icon, a flicker in the glide.
struct AchievementIcon: View {
    @Environment(\.seleneCanvas) private var canvas

    let appID: UInt32
    let file: String?
    /// Canvas units.
    let size: CGFloat
    /// Locked: Steam's gray icon, dimmed a little more on the page.
    var dimmed = false
    /// A secret not unlocked yet (`AchievementRow.isMasked`): blurred past reading, under the app's lock, as a
    /// failed port's art (maintainer's idea, 16 Nov 2026). The lock stays bright on a dimmed icon.
    var secret = false

    /// The file whose icon arrived while this view was on screen: only redraws it, the image is in `memory`.
    @State private var loaded: String?

    /// Every icon decoded this session, by game and file; the system may let some go under memory pressure.
    @MainActor private static let memory: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 400
        return cache
    }()

    private static func key(_ appID: UInt32, _ file: String) -> NSString { "\(appID)/\(file)" as NSString }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: canvas.u(size * 0.16), style: .continuous)
        // Read so the arrival redraws this view; the image itself comes from `memory`.
        let _ = loaded
        let image = file.flatMap { Self.memory.object(forKey: Self.key(appID, $0)) }
        ZStack {
            shape.fill(SeleneTheme.ink15)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: secret ? canvas.u(size * 0.09) : 0, opaque: true)
                    .transition(.opacity)
            }
        }
        .frame(width: canvas.u(size), height: canvas.u(size))
        .clipShape(shape)
        .opacity(dimmed ? 0.5 : 1)
        .overlay {
            if secret {
                MaterialIconView(.lock, size: max(16, size * 0.36))
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.55), radius: canvas.u(size * 0.05))
            }
        }
        .accessibilityHidden(true)
        .task(id: file) {
            guard let file, Self.memory.object(forKey: Self.key(appID, file)) == nil,
                  let url = await SteamMetadataService.shared.achievementIcon(appID: appID, file: file),
                  !Task.isCancelled else { return }
            // Read and decoded off the main thread; at most 2 MiB, already validated as an image.
            guard let decoded = await Task.detached(priority: .utility, operation: { Self.decode(url) }).value else { return }
            Self.memory.setObject(decoded, forKey: Self.key(appID, file))
            guard !Task.isCancelled else { return }
            withAnimation(SeleneTheme.quick) { loaded = file }
        }
    }

    /// The file's pixels decoded now, not at the first draw: NSImage(contentsOf:) leaves that to the main thread.
    private nonisolated static func decode(_ url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
