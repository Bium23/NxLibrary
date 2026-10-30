import Foundation
import AppKit
import ImageIO
import Combine

public enum ArtworkKind: String, Codable {
    case hero, logo, square
    /// A real Switch box cover (GameTDB), never a crop. Replaces the old `cover`
    /// kind (store images cropped to portrait), whose files are no longer read.
    case boxart

    /// Kinds cached as PNG so transparency survives.
    var isPNG: Bool { self == .logo || self == .square }

    public var maxPixelSize: CGFloat {
        switch self {
        case .hero: return 2560
        case .logo: return 1200
        case .square: return 512
        case .boxart: return 1400
        }
    }
}

public protocol ArtworkHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionArtworkClient: ArtworkHTTPClient {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

public final class ArtworkStore: ObservableObject {
    public let cacheDirectory: URL
    private let client: ArtworkHTTPClient
    private let fileManager: FileManager

    public init(cacheDirectory: URL = ArtworkStore.defaultDirectory(),
                client: ArtworkHTTPClient = URLSessionArtworkClient(),
                fileManager: FileManager = .default) {
        self.cacheDirectory = cacheDirectory
        self.client = client
        self.fileManager = fileManager
    }

    public static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NXLibrary/artwork")
    }

    public func cachedURL(titleID: String, kind: ArtworkKind) -> URL? {
        let safe = titleID.map {
            $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_"
        }.reduce(into: "") { $0.append($1) }
        let dir = cacheDirectory.appendingPathComponent(safe.isEmpty ? "unknown" : safe)
        let primaryExt = kind.isPNG ? "png" : "jpg"
        let fallbackExt = kind.isPNG ? "jpg" : "png"
        let primary = dir.appendingPathComponent("\(kind.rawValue).\(primaryExt)")
        if fileManager.fileExists(atPath: primary.path) { return primary }
        let fallback = dir.appendingPathComponent("\(kind.rawValue).\(fallbackExt)")
        if fileManager.fileExists(atPath: fallback.path) { return fallback }
        return nil
    }

    public func fetch(titleID: String, remoteURL: URL?, kind: ArtworkKind) async -> URL? {
        if let cached = cachedURL(titleID: titleID, kind: kind) { return cached }

        var targetURL = remoteURL
        if targetURL == nil && kind == .hero && titleID.count == 16 && titleID.hasPrefix("0100") {
            targetURL = URL(string: "https://api.nlib.cc/nx/\(titleID)/banner")
        }
        guard let fetchURL = targetURL else { return nil }

        var request = URLRequest(url: fetchURL)
        request.timeoutInterval = 15
        request.setValue("NXLibrary/0.1 (macOS; personal app)",
                         forHTTPHeaderField: "User-Agent")

        do {
            let (data, http) = try await client.data(for: request)
            guard (200..<300).contains(http.statusCode), !data.isEmpty else {
                if kind == .hero, fetchURL.absoluteString != "https://api.nlib.cc/nx/\(titleID)/banner",
                   titleID.count == 16, titleID.hasPrefix("0100") {
                    return await fetch(titleID: titleID,
                                       remoteURL: URL(string: "https://api.nlib.cc/nx/\(titleID)/banner"),
                                       kind: kind)
                }
                return cachedURL(titleID: titleID, kind: kind)
            }

            let url = fileURL(titleID: titleID, kind: kind)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)

            if kind == .logo {
                try data.write(to: url, options: .atomic)
                return url
            } else if kind == .square {
                let png = await Task.detached(priority: .utility) {
                    Self.downsample(data, maxPixelSize: ArtworkKind.square.maxPixelSize, png: true)
                }.value
                guard let png else { return cachedURL(titleID: titleID, kind: kind) }
                try png.write(to: url, options: .atomic)
                return url
            } else {
                let maxPixelSize = kind.maxPixelSize
                let jpeg = await Task.detached(priority: .utility) {
                    Self.downsample(data, maxPixelSize: maxPixelSize)
                }.value
                guard let jpeg else { return cachedURL(titleID: titleID, kind: kind) }
                try jpeg.write(to: url, options: .atomic)
                return url
            }
        } catch {
            if kind == .hero, fetchURL.absoluteString != "https://api.nlib.cc/nx/\(titleID)/banner",
               titleID.count == 16, titleID.hasPrefix("0100") {
                return await fetch(titleID: titleID,
                                   remoteURL: URL(string: "https://api.nlib.cc/nx/\(titleID)/banner"),
                                   kind: kind)
            }
            return cachedURL(titleID: titleID, kind: kind)
        }
    }

    /// Cached title screenshot (`screen-<index>.jpg`, max 1600 px). Cache hit needs no network.
    public func screenshot(titleID: String, index: Int, remoteURL: URL) async -> URL? {
        let safe = titleID.map {
            $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_"
        }.reduce(into: "") { $0.append($1) }
        let dir = cacheDirectory.appendingPathComponent(safe.isEmpty ? "unknown" : safe)
        let target = dir.appendingPathComponent("screen-\(index).jpg")
        if fileManager.fileExists(atPath: target.path) { return target }

        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 15
        request.setValue("NXLibrary/0.1 (macOS; personal app)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, http) = try await client.data(for: request)
            guard (200..<300).contains(http.statusCode), !data.isEmpty else { return nil }
            let jpeg = await Task.detached(priority: .utility) {
                Self.downsample(data, maxPixelSize: 1600)
            }.value
            guard let jpeg else { return nil }
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            try jpeg.write(to: target, options: .atomic)
            return target
        } catch {
            return nil
        }
    }

    public func cacheSize() -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            guard values?.isDirectory != true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    public func trimCache(maxBytes: Int64 = 300 * 1024 * 1024) {
        guard maxBytes > 0,
              let enumerator = fileManager.enumerator(
                at: cacheDirectory,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
              ) else { return }
        var files: [(URL, Int64, Date)] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
            )
            guard values?.isDirectory != true else { continue }
            files.append((url, Int64(values?.fileSize ?? 0),
                          values?.contentModificationDate ?? .distantPast))
        }
        var total = files.reduce(Int64(0)) { $0 + $1.1 }
        for file in files.sorted(by: { $0.2 < $1.2 }) where total > maxBytes {
            try? fileManager.removeItem(at: file.0)
            total -= file.1
        }
    }

    public func clear() {
        try? fileManager.removeItem(at: cacheDirectory)
    }

    private func fileURL(titleID: String, kind: ArtworkKind) -> URL {
        let safe = titleID.map {
            $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_"
        }.reduce(into: "") { $0.append($1) }
        let ext = kind.isPNG ? "png" : "jpg"
        return cacheDirectory
            .appendingPathComponent(safe.isEmpty ? "unknown" : safe)
            .appendingPathComponent("\(kind.rawValue).\(ext)")
    }

    /// A title ID as a safe folder name.
    static func folderName(for titleID: String) -> String {
        let safe = titleID.map {
            $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_"
        }.reduce(into: "") { $0.append($1) }
        return safe.isEmpty ? "unknown" : safe
    }

    static func downsample(_ data: Data, maxPixelSize: CGFloat, png: Bool = false) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: image)
        if png { return rep.representation(using: .png, properties: [:]) }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.94])
    }
}
