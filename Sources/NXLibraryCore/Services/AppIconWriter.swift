import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Writes the player's icon into a game app NX Library built, and puts the game's own icon back.
///
/// The engine packs the app with the game's icon (`Resources/AppIcon.icns`, `CFBundleIconFile`) and signs it ad hoc;
/// a NUP (Switch 2) or a dump carries no icon, so its app has none. This writes the icon the same way, marks
/// `Info.plist` with `NXLibraryAppIcon`, signs the bundle again ad hoc as the engine does and verifies it. The game's
/// own icon (or its absence) is kept beside NX Library's data the first time, so Restore needs no rebuild. A rebuild
/// replaces the whole app: its new Info.plist has no mark, so the next write keeps the new build's icon as the original.
/// Any failure puts back every file it touched, leaving the app as it was.
public struct AppIconWriter {
    public enum Failure: LocalizedError, Equatable {
        case notAnApp
        case notAnImage
        case iconFailed(String)
        case signingFailed(String)

        public var errorDescription: String? {
            switch self {
            case .notAnApp: return L10n.text("The game's app was not found.")
            case .notAnImage: return L10n.text("The icon is not an image NX Library can read.")
            case .iconFailed(let detail): return L10n.format("The icon could not be made: %@", [String(describing: (detail))])
            case .signingFailed(let detail): return L10n.format("The app could not be signed again, so it was left as it was: %@", [String(describing: (detail))])
            }
        }
    }

    /// The Info.plist key that marks an icon NX Library wrote.
    public static let markKey = "NXLibraryAppIcon"
    static let iconName = "AppIcon"

    /// Per game: the original icon (`original.icns`) or its absence (`original.json`).
    public let backups: URL
    private let runner: CommandRunning
    private let fileManager: FileManager
    private let codesign: URL
    private let iconutil: URL
    private let xattr: URL

    public init(backups: URL = AppData.supportRoot.appendingPathComponent("app-icons"),
                runner: CommandRunning = SystemCommandRunner(), fileManager: FileManager = .default,
                codesign: URL = URL(fileURLWithPath: "/usr/bin/codesign"),
                iconutil: URL = URL(fileURLWithPath: "/usr/bin/iconutil"),
                xattr: URL = URL(fileURLWithPath: "/usr/bin/xattr")) {
        self.backups = backups
        self.runner = runner
        self.fileManager = fileManager
        self.codesign = codesign
        self.iconutil = iconutil
        self.xattr = xattr
    }

    // MARK: - Reading

    /// The app has an icon of its own: one the engine packed (not one NX Library wrote).
    public func hasOwnIcon(_ app: URL) -> Bool {
        guard let info = try? plist(app), info[Self.markKey] as? Bool != true else { return false }
        return iconFile(app, info: info).map { fileManager.fileExists(atPath: $0.path) } ?? false
    }

    /// The game has an icon of its own, shown now or kept aside while NX Library's is shown: the choice to show the
    /// player's icon instead is worth asking. Without one there is nothing to lose.
    public func hasOriginalIcon(_ app: URL, key: String) -> Bool {
        if hasOwnIcon(app) { return true }
        return showsWrittenIcon(app)
            && fileManager.fileExists(atPath: backups.appendingPathComponent(key).appendingPathComponent("original.icns").path)
    }

    /// The game's image for Automatic previews, including the backup while a personal image is applied.
    public func originalIconURL(_ app: URL, key: String) -> URL? {
        if hasOwnIcon(app), let info = try? plist(app) { return iconFile(app, info: info) }
        let saved = backups.appendingPathComponent(key).appendingPathComponent("original.icns")
        return showsWrittenIcon(app) && fileManager.fileExists(atPath: saved.path) ? saved : nil
    }

    /// The app shows an icon NX Library wrote.
    public func showsWrittenIcon(_ app: URL) -> Bool {
        (try? plist(app))?[Self.markKey] as? Bool == true
    }

    // MARK: - Writing

    /// Reconcile a resolved image, including the absence of a replacement after removing a personal pick.
    /// Missing artwork restores the original/generic icon instead of leaving the old pick behind.
    @discardableResult
    public func update(image: Data?, app: URL, key: String) throws -> Bool {
        if let image {
            try apply(image: image, to: app, key: key)
            return true
        }
        guard showsWrittenIcon(app) else { return false }
        try restore(app, key: key)
        return true
    }

    /// Writes `image` (any format ImageIO reads; square art) as the app's icon. Slow for a large game: signing
    /// hashes the whole bundle, so call it off the main thread.
    public func apply(image: Data, to app: URL, key: String) throws {
        let info = try plist(app)
        if info[Self.markKey] as? Bool != true { try keepOriginal(app, info: info, key: key) }
        let work = try temporaryFolder()
        defer { try? fileManager.removeItem(at: work) }
        let icns = try makeICNS(image, in: work)
        try transaction(app, info: info, work: work) {
            let target = resources(app).appendingPathComponent("\(Self.iconName).icns")
            try fileManager.createDirectory(at: resources(app), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
            try fileManager.copyItem(at: icns, to: target)
            var updated = info
            updated["CFBundleIconFile"] = Self.iconName
            updated[Self.markKey] = true
            try writePlist(updated, app)
        }
    }

    /// Puts back the game's own icon (or none, for an app that had none). Nothing to do when the app shows its own.
    public func restore(_ app: URL, key: String) throws {
        let info = try plist(app)
        guard info[Self.markKey] as? Bool == true else { return }
        let folder = backups.appendingPathComponent(key)
        let original = folder.appendingPathComponent("original.icns")
        let hadIcon = fileManager.fileExists(atPath: original.path)
        let work = try temporaryFolder()
        defer { try? fileManager.removeItem(at: work) }
        try transaction(app, info: info, work: work) {
            let target = resources(app).appendingPathComponent("\(Self.iconName).icns")
            if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
            var updated = info
            updated.removeValue(forKey: Self.markKey)
            if hadIcon {
                try fileManager.copyItem(at: original, to: target)
                updated["CFBundleIconFile"] = Self.iconName
            } else {
                updated.removeValue(forKey: "CFBundleIconFile")
            }
            try writePlist(updated, app)
        }
    }

    // MARK: - Steps

    /// Keeps the app's icon as packed by the engine, replacing what an earlier build left.
    private func keepOriginal(_ app: URL, info: [String: Any], key: String) throws {
        let folder = backups.appendingPathComponent(key)
        try? fileManager.removeItem(at: folder)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        if let icon = iconFile(app, info: info), fileManager.fileExists(atPath: icon.path) {
            try fileManager.copyItem(at: icon, to: folder.appendingPathComponent("original.icns"))
        }
        let note = ["app": app.lastPathComponent, "hadIcon": iconFile(app, info: info) != nil ? "yes" : "no"]
        try JSONSerialization.data(withJSONObject: note, options: [.sortedKeys])
            .write(to: folder.appendingPathComponent("original.json"), options: .atomic)
    }

    /// Every size an .icns holds, from the image scaled to a square, through `iconutil`.
    func makeICNS(_ image: Data, in work: URL) throws -> URL {
        guard let source = CGImageSourceCreateWithData(image as CFData, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Failure.notAnImage }
        let cg = try Self.fullBleed(decoded)
        let set = work.appendingPathComponent("\(Self.iconName).iconset")
        try fileManager.createDirectory(at: set, withIntermediateDirectories: true)
        for side in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = scale == 1 ? "icon_\(side)x\(side).png" : "icon_\(side)x\(side)@2x.png"
                try writePNG(cg, side: side * scale, to: set.appendingPathComponent(name))
            }
        }
        let out = work.appendingPathComponent("\(Self.iconName).icns")
        let result = try runner.run(iconutil, ["-c", "icns", set.path, "-o", out.path],
                                    environment: nil, currentDirectory: nil)
        guard result.status == 0, fileManager.fileExists(atPath: out.path) else {
            throw Failure.iconFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return out
    }

    /// The image as an opaque square that fills the whole icon, as the engine's icons do. macOS 26 and later shrink an
    /// icon that leaves transparent edges or corners (art made for a launcher, with rounded corners or a margin) into a
    /// grey tile; an opaque full square is masked to the system's shape instead. Transparent margins are trimmed, and
    /// what stays transparent (rounded corners) takes the colour of the art's own edge.
    static func fullBleed(_ image: CGImage) throws -> CGImage {
        let side = min(max(image.width, image.height), 1024)
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let rgba = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = rgba.data else { throw Failure.notAnImage }
        rgba.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * width + x) * 4 + 3] }
        // Rows in memory run from the top: the box is in CGImage cropping coordinates.
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where alpha(x, y) > 127 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { throw Failure.notAnImage }
        // The edge colour: the average of the opaque pixels in a thin ring inside the box.
        let ring = max(1, min(maxX - minX, maxY - minY) / 25)
        var sum = (r: 0, g: 0, b: 0, n: 0)
        for y in minY...maxY {
            for x in minX...maxX {
                guard x - minX < ring || maxX - x < ring || y - minY < ring || maxY - y < ring else { continue }
                let i = (y * width + x) * 4
                guard pixels[i + 3] == 255 else { continue }
                sum.r += Int(pixels[i]); sum.g += Int(pixels[i + 1]); sum.b += Int(pixels[i + 2]); sum.n += 1
            }
        }
        let edge = sum.n > 0
            ? CGColor(srgbRed: CGFloat(sum.r) / CGFloat(sum.n * 255), green: CGFloat(sum.g) / CGFloat(sum.n * 255),
                      blue: CGFloat(sum.b) / CGFloat(sum.n * 255), alpha: 1)
            : CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        guard let trimmed = rgba.makeImage()?.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)),
              let square = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw Failure.notAnImage }
        square.interpolationQuality = .high
        square.setFillColor(edge)
        square.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let w = CGFloat(trimmed.width), h = CGFloat(trimmed.height), s = CGFloat(side)
        let scale = max(s / w, s / h)
        square.draw(trimmed, in: CGRect(x: (s - w * scale) / 2, y: (s - h * scale) / 2, width: w * scale, height: h * scale))
        guard let result = square.makeImage() else { throw Failure.notAnImage }
        return result
    }

    /// Scales the square image to one of the .icns sizes.
    private func writePNG(_ image: CGImage, side: Int, to url: URL) throws {
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw Failure.notAnImage
        }
        context.interpolationQuality = .high
        let w = CGFloat(image.width), h = CGFloat(image.height), s = CGFloat(side)
        let scale = max(s / w, s / h)
        context.draw(image, in: CGRect(x: (s - w * scale) / 2, y: (s - h * scale) / 2, width: w * scale, height: h * scale))
        guard let scaled = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.notAnImage
        }
        CGImageDestinationAddImage(destination, scaled, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.notAnImage }
    }

    /// Runs `change`, signs the bundle again and verifies it. On any failure every file the change or the signing can
    /// touch (Info.plist, the icon, the launcher with its signature, the resource seal) is put back as it was.
    private func transaction(_ app: URL, info: [String: Any], work: URL, _ change: () throws -> Void) throws {
        let executable = (info["CFBundleExecutable"] as? String).map { app.appendingPathComponent("Contents/MacOS/\($0)") }
        let touched = [app.appendingPathComponent("Contents/Info.plist"),
                       resources(app).appendingPathComponent("\(Self.iconName).icns"),
                       app.appendingPathComponent("Contents/_CodeSignature/CodeResources"),
                       executable].compactMap { $0 }
        let saved = work.appendingPathComponent("saved")
        try fileManager.createDirectory(at: saved, withIntermediateDirectories: true)
        var kept: [(URL, URL?)] = []
        for (index, file) in touched.enumerated() {
            if fileManager.fileExists(atPath: file.path) {
                let copy = saved.appendingPathComponent("\(index)")
                try fileManager.copyItem(at: file, to: copy)
                kept.append((file, copy))
            } else {
                kept.append((file, nil))
            }
        }
        func rollBack() {
            for (file, copy) in kept {
                try? fileManager.removeItem(at: file)
                if let copy { try? fileManager.copyItem(at: copy, to: file) }
            }
        }
        do {
            try change()
            try sign(app)
        } catch {
            rollBack()
            throw error
        }
    }

    /// Ad hoc, as the engine signs (`dm/mac/pack_app.py`): the bundle only, its inner host keeps its signature.
    /// Finder information on copied files makes codesign refuse the bundle: cleared and tried once more, as the engine does.
    private func sign(_ app: URL) throws {
        var result = try runner.run(codesign, ["--force", "--sign", "-", app.path], environment: nil, currentDirectory: nil)
        if result.status != 0, result.stderr.contains("detritus") || result.stderr.contains("not signed at all") {
            _ = try? runner.run(xattr, ["-cr", app.path], environment: nil, currentDirectory: nil)
            result = try runner.run(codesign, ["--force", "--sign", "-", app.path], environment: nil, currentDirectory: nil)
        }
        guard result.status == 0 else { throw Failure.signingFailed(Self.firstLine(result.stderr)) }
        let check = try runner.run(codesign, ["--verify", "--deep", "--strict", app.path], environment: nil, currentDirectory: nil)
        guard check.status == 0 else { throw Failure.signingFailed(Self.firstLine(check.stderr)) }
    }

    // MARK: - Bundle files

    private func resources(_ app: URL) -> URL { app.appendingPathComponent("Contents/Resources") }

    private func iconFile(_ app: URL, info: [String: Any]) -> URL? {
        guard let name = info["CFBundleIconFile"] as? String, !name.isEmpty else { return nil }
        let file = (name as NSString).pathExtension.isEmpty ? name + ".icns" : name
        return resources(app).appendingPathComponent(file)
    }

    private func plist(_ app: URL) throws -> [String: Any] {
        let url = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: url),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw Failure.notAnApp
        }
        return info
    }

    /// Keeps the file's format (the engine writes XML).
    private func writePlist(_ info: [String: Any], _ app: URL) throws {
        let url = app.appendingPathComponent("Contents/Info.plist")
        var format = PropertyListSerialization.PropertyListFormat.xml
        if let data = try? Data(contentsOf: url) {
            _ = try? PropertyListSerialization.propertyList(from: data, format: &format)
        }
        try PropertyListSerialization.data(fromPropertyList: info, format: format, options: 0).write(to: url, options: .atomic)
    }

    private func temporaryFolder() throws -> URL {
        let url = fileManager.temporaryDirectory.appendingPathComponent("nxlibrary-icon-\(UUID().uuidString)")
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func firstLine(_ text: String) -> String {
        text.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "codesign failed"
    }
}
