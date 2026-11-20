import Foundation

/// Mod images from GameBanana's CDN, kept on disk by URL. Only trusted GameBanana URLs are fetched; at most 4 at once.
public actor GameBananaImageCache {
    private let http: ArtworkHTTPClient
    private let folder: URL
    private let userAgent: String
    private let gate = GameBananaGate(limit: 4)

    public init(http: ArtworkHTTPClient = URLSessionArtworkClient(), folder: URL, userAgent: String) {
        self.http = http
        self.folder = folder
        self.userAgent = userAgent
    }

    /// The image on disk, downloading it first when needed; nil for an untrusted URL or a failed download.
    public func file(for url: URL) async -> URL? {
        guard GameBananaAPI.trusted(url) else { return nil }
        let ext = ["jpg", "jpeg", "png", "webp", "gif"].contains(url.pathExtension.lowercased()) ? url.pathExtension.lowercased() : "img"
        let file = folder.appendingPathComponent(GameBananaClient.hash(url.absoluteString)).appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: file.path) { return file }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        await gate.enter()
        let result = try? await http.data(for: request)
        await gate.leave()
        guard let (data, response) = result, (200..<300).contains(response.statusCode), !data.isEmpty else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (try? data.write(to: file, options: .atomic)) != nil ? file : nil
    }
}
