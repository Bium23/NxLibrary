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
    /// At most this many downloads at once; later requests wait for a free one (a screen of achievement
    /// icons asks for dozens together: refused, they stayed blank until their row was drawn again).
    static let concurrentDownloads = 6
    private var slotWaiters: [UUID: CheckedContinuation<Void, Error>] = [:]
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
        // `URL.path` drops the trailing slash; the components keep it.
        if url.host == SteamAchievementRarity.host {
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?.path == SteamAchievementRarity.path
        }
        return url.host == "store.steampowered.com" || SteamMetadata.safeImage(url) != nil
    }

    public init(directory: URL = AppData.supportRoot.appendingPathComponent("integrations/steam/enrichment"),
                transport: @escaping Transport = { try await SteamMetadataService.download($0) }) {
        self.directory = directory; self.transport = transport
    }
    public static func download(_ url: URL) async throws -> Data {
        guard allowed(url) else { throw URLError(.badURL) }
        var request = URLRequest(url: url); request.timeoutInterval = 15
        request.setValue(AppIdentity.userAgent(), forHTTPHeaderField: "User-Agent")
        let limit = url.host == "store.steampowered.com" || url.host == SteamAchievementRarity.host ? 2_097_152 : 12_582_912
        let (data, response) = try await BoundedDownload.data(for: request, session: session, limit: limit)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let final = http.url, allowed(final) else { throw URLError(.badServerResponse) }
        return data
    }
    private func release(_ url: URL, flightID: UUID, waiter: UUID) {
        guard var flight = pending[url], flight.id == flightID else { return }
        flight.waiters.remove(waiter)
        if flight.waiters.isEmpty { flight.task.cancel(); pending[url] = nil; wakeSlotWaiters() }
        else { pending[url] = flight }
    }
    /// Every waiter looks again: one may now share a flight that started meanwhile, or take the free slot.
    private func wakeSlotWaiters() {
        let waiting = slotWaiters.values
        slotWaiters.removeAll()
        waiting.forEach { $0.resume() }
    }
    private func waitForSlot() async throws {
        let id = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // Runs on the actor before `cancelWait` can: a cancellation before this point shows here.
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { slotWaiters[id] = continuation }
            }
        }, onCancel: { Task { await self.cancelWait(id) } })
    }
    private func cancelWait(_ id: UUID) {
        slotWaiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
    private func refuseIfFailedRecently(_ url: URL) throws {
        if let failed = failedAt[url], Date().timeIntervalSince(failed) < 60 { throw URLError(.resourceUnavailable) }
    }
    private func fetch(_ url: URL) async throws -> Data {
        try Task.checkCancellation()
        // A recent failure answers at once, before and after waiting for a slot (it may fail meanwhile).
        try refuseIfFailedRecently(url)
        while pending[url] == nil && pending.count >= Self.concurrentDownloads { try await waitForSlot() }
        try refuseIfFailedRecently(url)
        let waiter = UUID()
        var flight: Flight
        if let existing = pending[url] { flight = existing; flight.waiters.insert(waiter) }
        else {
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
    private static let metadataLanguages: Set<String> = ["english", "italian", "french", "german", "spanish", "brazilian", "schinese"]

    private func metadataFile(appID: UInt32, language: String) -> URL {
        directory.appendingPathComponent("\(appID)/\(language).json")
    }

    private func cachedMetadata(appID: UInt32, language: String) -> SteamMetadata? {
        let file = metadataFile(appID: appID, language: language)
        let cached = (try? InstallationFileSnapshot.read(at: file, maximumBytes: 2_097_152).data).flatMap { try? JSONDecoder().decode(SteamMetadata.self, from: $0) }
        return cached.flatMap { $0.appID == appID && $0.language == language ? $0 : nil }
    }

    /// The newest entry in any language, for a page offline in a new language: shown with its language notice
    /// (`GameDetailPresentation(steamRecord:)`) and asked again in the app language later.
    public func cachedInAnyLanguage(appID: UInt32) -> SteamMetadata? {
        Self.metadataLanguages.compactMap { cachedMetadata(appID: appID, language: $0) }.max { $0.fetchedAt < $1.fetchedAt }
    }

    /// The game's related row needs only scoring traits. Read existing entries and leave other games off the network.
    public func cachedRelatedTraits(appIDs: Set<UInt32>, language: String) -> [UInt32: MoreLikeThis.Traits] {
        guard Self.metadataLanguages.contains(language) else { return [:] }
        var traits: [UInt32: MoreLikeThis.Traits] = [:]
        for appID in appIDs where appID > 0 {
            guard !Task.isCancelled else { return [:] }
            if let cached = cachedMetadata(appID: appID, language: language) { traits[appID] = .init(steam: cached) }
        }
        return traits
    }

    public func metadata(appID: UInt32, language: String, refresh: Bool = false) async -> SteamMetadata? {
        guard appID > 0, Self.metadataLanguages.contains(language) else { return nil }
        let file = metadataFile(appID: appID, language: language)
        let valid = cachedMetadata(appID: appID, language: language)
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
    /// How many of Steam's players have each achievement (`SteamAchievementRarity`), by API name, kept for a day.
    /// Offline or on a bad answer, the last percentages known, or nil.
    public func achievementPercents(appID: UInt32) async -> [String: Double]? {
        guard appID > 0 else { return nil }
        let file = directory.appendingPathComponent("\(appID)/achievement-percents.json")
        let cached = (try? InstallationFileSnapshot.read(at: file, maximumBytes: 2_097_152).data)
            .flatMap { try? JSONDecoder().decode(SteamAchievementPercentsCache.self, from: $0) }
        if let cached, Date().timeIntervalSince(cached.fetchedAt) < SteamAchievementRarity.freshFor { return cached.percents }
        let url = SteamAchievementRarity.url(appID: appID)
        do {
            let bytes = try await fetch(url)
            try Task.checkCancellation()
            let percents: [String: Double]
            do { percents = try SteamAchievementRarity.decode(bytes) }
            catch { failedAt[url] = Date(); throw error }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(SteamAchievementPercentsCache(fetchedAt: Date(), percents: percents)).write(to: file, options: .atomic)
            return percents
        } catch { return cached?.percents }
    }

    /// An achievement's icon from Steam's CDN, kept on disk as long as it reads as an image.
    public func achievementIcon(appID: UInt32, file name: String) async -> URL? {
        guard appID > 0, !Task.isCancelled, let url = SteamAchievementRarity.iconURL(appID: appID, file: name) else { return nil }
        let file = directory.appendingPathComponent("\(appID)/achievements/\(name)")
        let limit = 2_097_152
        if let data = try? InstallationFileSnapshot.read(at: file, maximumBytes: limit).data,
           ArtworkStore.downsample(data, maxPixelSize: 256) != nil { return file }
        guard let data = try? await fetch(url), !Task.isCancelled else { return nil }
        guard data.count <= limit, ArtworkStore.downsample(data, maxPixelSize: 256) != nil else { failedAt[url] = Date(); return nil }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            return file
        } catch { return nil }
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
