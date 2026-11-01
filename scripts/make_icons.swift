import AppKit
import Foundation

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let out = repo.appendingPathComponent("Resources")
let iconset = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// The source is a full-bleed square. Apply the macOS silhouette here once,
// then downsample that master for both Finder and the dynamic Dock icon.
let masterURL = out.appendingPathComponent("IconArtwork.png")
guard let artwork = NSImage(contentsOf: masterURL) else {
    fatalError("Missing icon artwork: \(masterURL.path)")
}

func macOSIcon(_ artwork: NSImage) -> NSImage {
    let image = NSImage(size: NSSize(width: 1024, height: 1024))
    image.lockFocus()
    defer { image.unlockFocus() }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }

    let tileRect = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tile = NSBezierPath(roundedRect: tileRect, xRadius: 185, yRadius: 185)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 14
    shadow.shadowOffset = NSSize(width: 0, height: -7)
    shadow.set()
    NSColor(srgbRed: 0.137, green: 0.141, blue: 0.149, alpha: 1).setFill()
    tile.fill()
    NSShadow().set()
    tile.addClip()
    NSGraphicsContext.current?.imageInterpolation = .high
    artwork.draw(in: tileRect, from: .zero, operation: .sourceOver, fraction: 1)
    return image
}

func monochrome(_ image: NSImage) -> NSImage {
    guard let data = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: data),
          let gray = bitmap.converting(to: .genericGray, renderingIntent: .default) else {
        fatalError("Unable to create monochrome icon")
    }
    let result = NSImage(size: image.size)
    result.addRepresentation(gray)
    return result
}

func png(_ image: NSImage, pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
               from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let master = macOSIcon(artwork)
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    if let data = png(master, pixels: px) {
        try data.write(to: iconset.appendingPathComponent("\(name).png"))
    }
}

for variant in ["light", "dark", "mono"] {
    let image = variant == "mono" ? monochrome(master) : master
    if let data = png(image, pixels: 1024) {
        try data.write(to: out.appendingPathComponent("AppIcon-\(variant.capitalized).png"))
    }
}

// Package all standard Finder sizes into the bundle icon as well.
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", out.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil failed: \(iconutil.terminationStatus)")
}
try FileManager.default.removeItem(at: iconset)
