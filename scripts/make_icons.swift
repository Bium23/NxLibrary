import AppKit
import Foundation

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let out = repo.appendingPathComponent("Resources")
let iconset = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func roundedFont(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .heavy)
    if let desc = base.fontDescriptor.withDesign(.rounded),
       let font = NSFont(descriptor: desc, size: size) { return font }
    return base
}

func drawMaster(_ variant: String) -> NSImage {
    let size = NSSize(width: 1024, height: 1024)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    let coral = NSColor(srgbRed: 1.0, green: 0.35, blue: 0.37, alpha: 1)
    let cyan = NSColor(srgbRed: 0.35, green: 0.78, blue: 0.98, alpha: 1)
    let graphite = NSColor(srgbRed: 0.082, green: 0.082, blue: 0.09, alpha: 1)
    let white = NSColor.white

    let rect = NSRect(x: 40, y: 40, width: 944, height: 944)
    let path = NSBezierPath(roundedRect: rect, xRadius: 200, yRadius: 200)
    path.addClip()

    let background: NSColor
    let foreground: NSColor
    switch variant {
    case "light":
        background = coral
        foreground = white
    case "mono":
        background = graphite
        foreground = white
    default:
        background = graphite
        foreground = white
    }
    NSGradient(colors: [background, background.blended(withFraction: 0.18, of: .black) ?? background])?
        .draw(in: path, angle: -90)

    // Inner coral glow for the dark icon.
    if variant == "dark" || variant == "appicon" {
        NSGradient(colors: [coral.withAlphaComponent(0.22), .clear])?
            .draw(in: NSBezierPath(ovalIn: NSRect(x: -180, y: 480, width: 900, height: 700)), angle: 45)
    }

    let font = roundedFont(390)
    let text = "NX" as NSString
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: foreground,
        .kern: -12,
    ]
    let textSize = text.size(withAttributes: attributes)
    let textPoint = NSPoint(x: (1024 - textSize.width) / 2,
                            y: (1024 - textSize.height) / 2 + 40)
    text.draw(at: textPoint, withAttributes: attributes)

    // Coral underline.
    let underline = NSBezierPath(roundedRect: NSRect(x: 322, y: 250, width: 380, height: 30),
                                 xRadius: 15, yRadius: 15)
    coral.setFill()
    underline.fill()

    // Cyan selection dot.
    let ring = NSBezierPath(ovalIn: NSRect(x: 748, y: 748, width: 70, height: 70))
    cyan.setStroke()
    ring.lineWidth = 18
    ring.stroke()

    NSColor.white.withAlphaComponent(0.12).setStroke()
    let border = NSBezierPath(roundedRect: rect, xRadius: 200, yRadius: 200)
    border.lineWidth = 6
    border.stroke()

    return image
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
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
               from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let master = drawMaster("appicon")
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
    let image = drawMaster(variant)
    if let data = png(image, pixels: 240) {
        try data.write(to: out.appendingPathComponent("AppIcon-\(variant.capitalized).png"))
    }
}
