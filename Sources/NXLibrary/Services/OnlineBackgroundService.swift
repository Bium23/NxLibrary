import AppKit
import CryptoKit
import NXLibraryCore

/// Online backgrounds: listings (cached for the session), the chosen file
/// (downloaded with progress into Wallpapers/online or live, with its credit),
/// and tile thumbnails (on disk for a week). Requests to a source's API are
/// spaced to its limit: Wallhaven 45 a minute, the others one a second.
actor OnlineBackgroundService {
    static let shared = OnlineBackgroundService()

    static let userAgent = "NXLibrary/0.1 (personal macOS app)"
    private static let spacing: [BackgroundSourceID: TimeInterval] = [.wallhaven: 60.0 / 45, .danbooru: 1,
                                                                      .motionbgs: 1, .steam: 1]
    private let session: URLSession
    private var pages: [URL: OnlinePage] = [:]
    private var nextSlot: [BackgroundSourceID: Date] = [:]

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        session = URLSession(configuration: configuration)
    }

    /// The Wallpapers folder beside the player's own (custom/, online/, live/, credits.json).
    static var wallpapersFolder: URL {
        SeleneImporter.defaultDestination.appendingPathComponent("Wallpapers", isDirectory: true)
    }

    // MARK: - Listings

    func page(_ source: BackgroundSourceID, category: BackgroundCategory, query: String,
              page number: Int) async throws -> OnlinePage {
        let url: URL?
        switch source {
        case .wallhaven: url = WallhavenAPI.searchURL(category, query: query, page: number)
        case .danbooru: url = DanbooruAPI.postsURL(category, query: query, page: number)
        case .motionbgs, .steam: url = nil
        }
        guard let url else { return OnlinePage(items: [], hasMore: false) }
        if let cached = pages[url] { return cached }
        let data = try await fetch(url, pacedFor: source)
        let page = source == .wallhaven ? try WallhavenAPI.parseSearch(data) : try DanbooruAPI.parsePosts(data)
        pages[url] = page
        return page
    }

    /// Waits for the source's next free slot, then fetches.
    private func fetch(_ url: URL, pacedFor source: BackgroundSourceID) async throws -> Data {
        let now = Date()
        let slot = max(now, nextSlot[source] ?? now)
        nextSlot[source] = slot.addingTimeInterval(Self.spacing[source] ?? 1)
        let wait = slot.timeIntervalSince(now)
        if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: - Download

    /// Downloads the full file, records its credit and returns the wallpaper id.
    func download(_ item: OnlineBackground, progress: @escaping @Sendable (Double) -> Void) async throws -> String {
        guard let remote = item.fileURL else { throw URLError(.fileDoesNotExist) }
        var title = item.title
        var author = item.author
        if item.source == .wallhaven,
           let data = try? await fetch(WallhavenAPI.detailURL(sourceID: item.sourceID), pacedFor: .wallhaven),
           let detail = try? WallhavenAPI.parseDetail(data) {
            title = detail.title ?? title
            author = detail.author ?? author
        }
        let delegate = DownloadProgress(progress)
        let (temporary, response) = try await session.download(from: remote, delegate: delegate)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: temporary)
            throw URLError(.badServerResponse)
        }
        let folder = Self.wallpapersFolder.appendingPathComponent(OnlineDownload.folder(for: item.kind), isDirectory: true)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(OnlineDownload.fileName(for: item, fileURL: remote))
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.moveItem(at: temporary, to: destination)

        let id = OnlineDownload.wallpaperID(for: item)
        let creditsFile = Self.wallpapersFolder.appendingPathComponent(BackgroundCredits.fileName)
        var credits = BackgroundCredits.load(from: creditsFile)
        credits[id] = BackgroundCredit(source: item.source, title: title, author: author, pageURL: item.pageURL,
                                       width: item.width, height: item.height)
        try BackgroundCredits.save(credits, to: creditsFile)
        return id
    }

    /// Forgets a removed download's credit.
    static func forgetCredit(for id: String) {
        let file = wallpapersFolder.appendingPathComponent(BackgroundCredits.fileName)
        var credits = BackgroundCredits.load(from: file)
        guard credits.removeValue(forKey: id) != nil else { return }
        try? BackgroundCredits.save(credits, to: file)
    }

    // MARK: - Thumbnails

    private static let thumbnailLife: TimeInterval = 7 * 24 * 3600
    private var pruned = false

    private static var thumbnailFolder: URL {
        ArtworkStore.defaultDirectory().appendingPathComponent("online-thumbs", isDirectory: true)
    }

    /// The thumbnail's file, fetched (no pacing: these come from the sources' image hosts) when missing or stale.
    func thumbnailFile(for url: URL) async -> URL? {
        let fileManager = FileManager.default
        let folder = Self.thumbnailFolder
        if !pruned {
            pruned = true
            pruneThumbnails(in: folder)
        }
        let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = folder.appendingPathComponent(name + "." + (url.pathExtension.isEmpty ? "jpg" : url.pathExtension))
        if let modified = (try? fileManager.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < Self.thumbnailLife {
            return file
        }
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        guard (try? data.write(to: file, options: .atomic)) != nil else { return nil }
        return file
    }

    private func pruneThumbnails(in folder: URL) {
        let fileManager = FileManager.default
        let files = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, Date().timeIntervalSince(modified) > Self.thumbnailLife {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}

/// Reports a download's share done.
private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let report: @Sendable (Double) -> Void
    init(_ report: @escaping @Sendable (Double) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        report(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
