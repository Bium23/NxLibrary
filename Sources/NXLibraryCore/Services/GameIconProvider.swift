import AppKit
import Combine
import ImageIO

/// View bodies only consult memory. Disk hits run independently of slow bundle reads so an
/// unavailable share can't hold cached artwork for other games behind it.
@MainActor
public final class GameIconProvider: ObservableObject {
    public static let shared = GameIconProvider()
    private let placeholder = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)
        ?? NSImage(size: NSSize(width: 64, height: 64))
    private let directory: URL
    private let disk = DispatchQueue(label: "local.nxlibrary.icon-cache", qos: .utility)
    private let sources = OperationQueue()
    private let read: @Sendable (Revision) -> Data?
    private let images = NSCache<NSUUID, NSImage>()
    private var entries: [UUID: Entry] = [:]

    struct Revision: Codable, Equatable, Sendable {
        let titleId: String?
        let app: URL
        let date: Date
        let workspace: String?
    }

    private struct Thumbnail: Codable {
        let revision: Revision
        let png: Data
    }

    private struct Entry {
        let revision: Revision
        let token = UUID()
        var loading = true
        var retryAfter = Date.distantPast
    }

    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NXLibrary/GameIcons", isDirectory: true),
         read: @escaping @Sendable (Revision) -> Data? = { GameIconProvider.readThumbnail($0) }) {
        self.directory = directory
        self.read = read
        sources.maxConcurrentOperationCount = 2
        sources.qualityOfService = .utility
        images.countLimit = 128
    }

    public func icon(for game: PortedGame) -> NSImage {
        squareArt(for: game) ?? placeholder
    }

    public func squareArt(for game: PortedGame) -> NSImage? {
        let revision = Revision(titleId: game.titleId, app: game.url, date: game.modificationDate, workspace: game.workspacePath)
        let id = game.id
        if let entry = entries[id], entry.revision == revision {
            if let image = images.object(forKey: id as NSUUID) { return image }
            if entry.loading || entry.retryAfter > Date() { return nil }
        }

        let entry = Entry(revision: revision)
        entries[id] = entry
        images.removeObject(forKey: id as NSUUID)
        let file = cacheFile(id)
        let read = self.read
        let sources = self.sources
        disk.async {
            if let data = try? Data(contentsOf: file),
               let thumbnail = try? PropertyListDecoder().decode(Thumbnail.self, from: data),
               thumbnail.revision == revision, let image = NSImage(data: thumbnail.png) {
                Task { @MainActor in self.finish(image, id: id, entry: entry) }
                return
            }
            sources.addOperation {
                let data = read(revision)
                let image = data.flatMap(NSImage.init(data:))
                Task { @MainActor in
                    guard self.entries[id]?.token == entry.token else { return }
                    if let data, image != nil {
                        self.disk.async {
                            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                                     withIntermediateDirectories: true)
                            if let record = try? PropertyListEncoder().encode(Thumbnail(revision: revision, png: data)) {
                                try? record.write(to: file, options: .atomic)
                            }
                        }
                    }
                    self.finish(image, id: id, entry: entry)
                }
            }
        }
        return nil
    }

    private func finish(_ image: NSImage?, id: UUID, entry: Entry) {
        guard entries[id]?.token == entry.token else { return }
        entries[id]?.loading = false
        if let image {
            images.setObject(image, forKey: id as NSUUID)
            objectWillChange.send()
        } else {
            entries[id]?.retryAfter = Date().addingTimeInterval(30)
        }
    }

    private func cacheFile(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: false)
    }

    public func forget(_ game: PortedGame) {
        entries.removeValue(forKey: game.id)
        images.removeObject(forKey: game.id as NSUUID)
        let file = cacheFile(game.id)
        disk.async { try? FileManager.default.removeItem(at: file) }
        objectWillChange.send()
    }

    nonisolated static func readThumbnail(_ revision: Revision) -> Data? {
        var urls: [URL] = []
        if revision.app.pathExtension.lowercased() == "app", let bundle = Bundle(url: revision.app) {
            let name = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String ?? "AppIcon"
            let file = (name as NSString).pathExtension.isEmpty ? name + ".icns" : name
            urls.append(revision.app.appendingPathComponent("Contents/Resources/" + file))
        }
        if let path = revision.workspace, let id = revision.titleId, !id.isEmpty {
            urls.append(URL(fileURLWithPath: path).appendingPathComponent("\(id)_build/extract/v0/icon.jpg"))
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                       kCGImageSourceCreateThumbnailWithTransform: true,
                                       kCGImageSourceThumbnailMaxPixelSize: 512]
        for url in urls {
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            }
        }
        return nil
    }
}
