import Foundation
import CryptoKit

public enum GameBananaError: Error, Equatable {
    /// No network: the store says so; installed mods keep working.
    case offline
    /// GameBanana answered with an error or something that is not the expected JSON.
    case unavailable
}

/// A small async gate: at most `limit` holders at once, the rest wait in order.
actor GameBananaGate {
    private let limit: Int
    private var holders = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = max(1, limit) }

    func enter() async {
        if holders < limit {
            holders += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Hands the slot to the next waiter, or frees it.
    func leave() {
        if waiters.isEmpty { holders -= 1 } else { waiters.removeFirst().resume() }
    }
}

/// GameBanana's API with good manners: one User-Agent, a 15 s timeout, at most 4 requests at once, and responses
/// cached on disk (game searches 1 day, mod pages 6 h, archive listings forever, since a file's contents never
/// change; an empty listing is not kept, since GameBanana may still be reading a new file). When the network fails, an expired cache entry is used rather than nothing.
public actor GameBananaClient {
    public static func userAgent(version: String) -> String { "NXLibrary/\(version) (macOS; personal app)" }

    private let http: ArtworkHTTPClient
    private let cacheFolder: URL
    private let userAgent: String
    private let now: @Sendable () -> Date
    private let gate: GameBananaGate

    public init(http: ArtworkHTTPClient = URLSessionArtworkClient(), cacheFolder: URL, userAgent: String,
                now: @escaping @Sendable () -> Date = { Date() }, maxConcurrent: Int = 4) {
        self.http = http
        self.cacheFolder = cacheFolder
        self.userAgent = userAgent
        self.now = now
        self.gate = GameBananaGate(limit: maxConcurrent)
    }

    public func searchGames(_ name: String) async throws -> [GameBananaGame] {
        try await fetch(GameBananaAPI.gameSearchURL(name), kind: "search", key: Self.hash(name.lowercased()),
                        lifetime: 86400) { try? JSONDecoder().decode(GameBananaGamePage.self, from: $0).records }
    }

    public func modPage(gameID: Int, page: Int, perPage: Int) async throws -> GameBananaModPage {
        try await fetch(GameBananaAPI.modIndexURL(gameID: gameID, page: page, perPage: perPage), kind: "index",
                        key: "\(gameID)-\(page)-\(perPage)", lifetime: 6 * 3600) {
            try? JSONDecoder().decode(GameBananaModPage.self, from: $0)
        }
    }

    public func profile(modID: Int) async throws -> GameBananaModProfile {
        try await fetch(GameBananaAPI.profileURL(modID: modID), kind: "profile", key: "\(modID)", lifetime: 6 * 3600) {
            try? JSONDecoder().decode(GameBananaModProfile.self, from: $0)
        }
    }

    public func archivePaths(fileID: Int) async throws -> [String] {
        try await fetch(GameBananaAPI.archiveListURL(fileID: fileID), kind: "listing", key: "\(fileID)", lifetime: nil,
                        keep: { !$0.isEmpty }) {
            GameBananaAPI.archivePaths(in: $0)
        }
    }

    // MARK: - Internals

    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// `lifetime` nil keeps the entry forever; `keep` says whether an answer is saved at all.
    private func fetch<T>(_ url: URL, kind: String, key: String, lifetime: TimeInterval?,
                          keep: (T) -> Bool = { _ in true }, parse: (Data) -> T?) async throws -> T {
        let file = cacheFolder.appendingPathComponent(kind).appendingPathComponent(key + ".json")
        let cached = (try? Data(contentsOf: file)).flatMap(parse).flatMap { keep($0) ? $0 : nil }
        if let cached, let lifetime, let saved = Self.savedDate(file), now().timeIntervalSince(saved) < lifetime {
            return cached
        }
        if let cached, lifetime == nil { return cached }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        await gate.enter()
        let outcome: Result<(Data, HTTPURLResponse), Error>
        do { outcome = .success(try await http.data(for: request)) } catch { outcome = .failure(error) }
        await gate.leave()

        switch outcome {
        case .success(let (data, response)):
            if (200..<300).contains(response.statusCode), let value = parse(data) {
                if keep(value) { store(data, at: file) }
                return value
            }
            if let cached { return cached }
            throw GameBananaError.unavailable
        case .failure(let error):
            if let cached { return cached }
            throw Self.map(error)
        }
    }

    private func store(_ data: Data, at file: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? data.write(to: file, options: .atomic)) != nil else { return }
        try? fm.setAttributes([.modificationDate: now()], ofItemAtPath: file.path)
    }

    private static func savedDate(_ file: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }

    static func map(_ error: Error) -> GameBananaError {
        guard let error = error as? URLError else { return .unavailable }
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .timedOut,
             .dataNotAllowed, .internationalRoamingOff:
            return .offline
        default:
            return .unavailable
        }
    }
}
