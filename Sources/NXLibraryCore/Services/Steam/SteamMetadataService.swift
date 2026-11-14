import Foundation
import CryptoKit

/// Bounded, source-specific enrichment. Failures preserve disk cache; no catalog
/// writes, credentials, game-content reads or Nintendo lookups.
public actor SteamMetadataService {
    public typealias Transport = @Sendable (URL) async throws -> Data
    public static let shared = SteamMetadataService()
    private let directory: URL
    private let transport: Transport
    private struct Flight {
        let id: UUID
        let task: Task<Data, Error>
        var waiters: Set<UUID>
    }
    private var pending: [URL: Flight] = [:]
    private var failedAt: [URL: Date] = [:]
    public static let resourceDeadline: TimeInterval = 20
    final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = resourceDeadline
        config.timeoutIntervalForRequest = 10
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }()
    public static func allowed(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return false }
        return url.host == "store.steampowered.com" || SteamMetadata.safeImage(url) != nil
    }

    public init(directory: URL = AppData.supportRoot.appendingPathComponent("integrations/steam/enrichment"),
                transport: @escaping Transport = { try await SteamMetadataService.download($0) }) {
        self.directory = directory; self.transport = transport
    }
    public static func download(_ url: URL) async throws -> Data {
        guard allowed(url) else { throw URLError(.badURL) }
        var request = URLRequest(url: url); request.timeoutInterval = 15
        request.setValue("NXLibrary/0.1 (macOS)", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let final = http.url, allowed(final) else { throw URLError(.badServerResponse) }
        let limit = url.host == "store.steampowered.com" ? 2_097_152 : 12_582_912
        if response.expectedContentLength > limit { throw URLError(.dataLengthExceedsMaximum) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }
    private func release(_ url: URL, flightID: UUID, waiter: UUID) {
        guard var flight = pending[url], flight.id == flightID else { return }
        flight.waiters.remove(waiter)
        if flight.waiters.isEmpty { flight.task.cancel(); pending[url] = nil }
        else { pending[url] = flight }
    }
    private func fetch(_ url: URL) async throws -> Data {
        try Task.checkCancellation()
        if let failed = failedAt[url], Date().timeIntervalSince(failed) < 60 { throw URLError(.resourceUnavailable) }
        let waiter = UUID()
        var flight: Flight
        if let existing = pending[url] { flight = existing; flight.waiters.insert(waiter) }
        else {
            guard pending.count < 6 else { throw URLError(.resourceUnavailable) }
            let transport = transport
            flight = Flight(id: UUID(), task: Task { try await transport(url) }, waiters: [waiter])
        }
        pending[url] = flight
        let id = flight.id, task = flight.task
        return try await withTaskCancellationHandler(operation: {
            defer { release(url, flightID: id, waiter: waiter) }
            do { let data = try await task.value; try Task.checkCancellation(); return data }
            catch {
                if !Task.isCancelled && !(error is CancellationError) { failedAt[url] = Date() }
                throw error
            }
        }, onCancel: { Task { await self.release(url, flightID: id, waiter: waiter) } })
    }
    public func metadata(appID: UInt32, language: String, refresh: Bool = false) async -> SteamMetadata? {
        guard appID > 0, ["english","italian","french","german","spanish","brazilian"].contains(language) else { return nil }
        let file = directory.appendingPathComponent("\(appID)/\(language).json")
        let cached = (try? InstallationFileSnapshot.read(at: file, maximumBytes: 2_097_152).data).flatMap { try? JSONDecoder().decode(SteamMetadata.self, from: $0) }
        let valid = cached.flatMap { $0.appID == appID && $0.language == language ? $0 : nil }
        if let valid, !refresh, Date().timeIntervalSince(valid.fetchedAt) < 604800 { return valid }
        let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(appID)&l=\(language)")!
        do {
            let bytes = try await fetch(url)
            try Task.checkCancellation()
            let result: SteamMetadata
            do { result = try SteamMetadata.decode(bytes, appID: appID, language: language) }
            catch { failedAt[url] = Date(); throw error }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(result).write(to: file, options: .atomic)
            return result
        } catch { return valid }
    }
    public func image(appID: UInt32, slot: ArtworkSlot, remote: URL? = nil) async -> URL? {
        guard appID > 0, !Task.isCancelled else { return nil }
        // Screenshots use their full URL in the cache key; no basename collisions.
        let token = remote.map { SHA256.hash(data: Data($0.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined() }
        let file = directory.appendingPathComponent("\(appID)/images/\(token ?? slot.rawValue).png")
        let cached = try? InstallationFileSnapshot.read(at: file, maximumBytes: 12_582_912).data
        let validCache = cached.flatMap { ArtworkStore.downsample($0, maxPixelSize: slot.kind.maxPixelSize, png: true) } != nil
        let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if validCache, let modified, Date().timeIntervalSince(modified) < 604800 { return file }
        let candidates = remote.map { [ArtworkCandidate(slot: slot, source: "Steam", url: $0)] }
            ?? SteamStoreArt.candidates(appID: Int(appID), slot: slot)
        for candidate in candidates {
            for url in [candidate.url, candidate.fallback].compactMap({ $0 }).compactMap(SteamMetadata.safeImage) {
                guard !Task.isCancelled else { return validCache ? file : nil }
                guard let data = try? await fetch(url) else { continue }
                guard !Task.isCancelled else { return validCache ? file : nil }
                guard data.count <= 12_582_912,
                      let image = ArtworkStore.downsample(data, maxPixelSize: slot.kind.maxPixelSize, png: true) else { failedAt[url] = Date(); continue }
                do {
                    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try image.write(to: file, options: .atomic); return file
                } catch { return nil }
            }
        }
        return validCache ? file : nil
    }
}
