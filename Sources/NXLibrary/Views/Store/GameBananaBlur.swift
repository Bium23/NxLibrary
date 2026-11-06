import SwiftUI
import AppKit
import CoreImage
import ImageIO

/// A mod's art, small and blurred once, kept in memory: the Featured banner's ground and the art behind the Mods
/// card. Blurring a 240-pixel image once is far cheaper than blurring the full art on every frame of a glide.
enum GameBananaBlur {
    /// The Featured banner's blur; the backdrop behind the card is softer still.
    static let bannerRadius: CGFloat = 8

    nonisolated(unsafe) private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        return cache
    }()
    nonisolated(unsafe) private static let context = CIContext(options: [.cacheIntermediates: false])

    private static func key(_ url: URL, _ radius: CGFloat) -> NSString { "\(Int(radius))|\(url.absoluteString)" as NSString }

    static func cached(for url: URL, radius: CGFloat) -> NSImage? { cache.object(forKey: key(url, radius)) }

    static func image(for url: URL, radius: CGFloat) async -> NSImage? {
        let key = key(url, radius)
        if let image = cache.object(forKey: key) { return image }
        guard let file = await GameBananaServices.shared.images.file(for: url) else { return nil }
        let image = await Task.detached(priority: .utility) { render(file, radius: radius) }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    nonisolated private static func render(_ file: URL, radius: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let small = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 240
              ] as CFDictionary) else { return nil }
        let input = CIImage(cgImage: small)
        let blurred = input.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(radius))
            .cropped(to: input.extent)
        guard let output = context.createCGImage(blurred, from: input.extent) else { return nil }
        return NSImage(cgImage: output, size: NSSize(width: output.width, height: output.height))
    }
}

/// A mod's blurred art filling its frame; empty until it is ready, then it fades in.
struct GameBananaBlurView: View {
    let url: URL?
    var radius: CGFloat = GameBananaBlur.bannerRadius
    @State private var image: NSImage?

    init(url: URL?, radius: CGFloat = GameBananaBlur.bannerRadius) {
        self.url = url
        self.radius = radius
        _image = State(initialValue: url.flatMap { GameBananaBlur.cached(for: $0, radius: radius) })
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            }
        }
        .clipped()
        .task(id: url) {
            guard let url else { image = nil; return }
            if let cached = GameBananaBlur.cached(for: url, radius: radius) {
                if image !== cached { image = cached }
                return
            }
            guard let loaded = await GameBananaBlur.image(for: url, radius: radius), !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { image = loaded }
        }
    }
}
