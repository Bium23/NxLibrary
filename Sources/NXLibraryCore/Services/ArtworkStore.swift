import Foundation
import AppKit
import ImageIO
import Combine

public enum ArtworkKind: String, Codable {
    case hero, cover

    var maxPixelSize: CGFloat {
        switch self {
        case .hero: return 2560
        case .cover: return 1000
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
        let url = fileURL(titleID: titleID, kind: kind)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return url
    }

    public func fetch(titleID: String, remoteURL: URL?, kind: ArtworkKind) async -> URL? {
        if let cached = cachedURL(titleID: titleID, kind: kind) { return cached }
        guard let remoteURL else { return nil }

        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 15
        request.setValue("NXLibrary/0.1 (macOS; personal app)",
                         forHTTPHeaderField: "User-Agent")

        do {
            let (data, http) = try await client.data(for: request)
            let maxPixelSize = kind.maxPixelSize
            let jpeg = await Task.detached(priority: .utility) {
                Self.downsample(data, maxPixelSize: maxPixelSize)
            }.value
            guard (200..<300).contains(http.statusCode), let jpeg else {
                return cachedURL(titleID: titleID, kind: kind)
            }
            let url = fileURL(titleID: titleID, kind: kind)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            try jpeg.write(to: url, options: .atomic)
            return url
        } catch {
            return cachedURL(titleID: titleID, kind: kind)
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
        return cacheDirectory
            .appendingPathComponent(safe.isEmpty ? "unknown" : safe)
            .appendingPathComponent("\(kind.rawValue).jpg")
    }

    static func downsample(_ data: Data, maxPixelSize: CGFloat) -> Data? {
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
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
