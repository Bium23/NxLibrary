import Foundation

public enum SquareGridLookup: Equatable {
    case found(URL)
    case noGrid
    case failed
}

/// Per-session, in-memory memo of games with a definite "no square grid"
/// answer. Keyed by game id + API key so a new key retries. Never persisted.
public final class SquareGridMemo: @unchecked Sendable {
    public static let shared = SquareGridMemo()
    private let lock = NSLock()
    private var keys = Set<String>()
    public init() {}

    public static func shouldRemember(_ result: SquareGridLookup, cancelled: Bool) -> Bool {
        !cancelled && result == .noGrid
    }

    private func key(_ id: UUID, _ apiKey: String) -> String { "\(id.uuidString)|\(apiKey)" }

    public func contains(_ id: UUID, apiKey: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return keys.contains(key(id, apiKey))
    }

    public func record(_ result: SquareGridLookup, cancelled: Bool, id: UUID, apiKey: String) {
        guard Self.shouldRemember(result, cancelled: cancelled) else { return }
        lock.lock(); defer { lock.unlock() }
        keys.insert(key(id, apiKey))
    }
}

public final class SteamGridDBService: Sendable {
    public init() {}

    private struct AutocompleteResponse: Decodable {
        let success: Bool
        let data: [GameItem]?

        struct GameItem: Decodable {
            let id: Int
            let name: String
        }
    }

    private struct MediaResponse: Decodable {
        let success: Bool
        let data: [MediaItem]?

        struct MediaItem: Decodable {
            let id: Int
            let url: String
            let thumb: String?
            let width: Int?
            let height: Int?
            let mime: String?
        }
    }

    public func fetchLogoURL(gameName: String, apiKey: String) async -> URL? {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let gameId = await findGameId(gameName: gameName, apiKey: apiKey) else { return nil }

        let endpoint = "https://www.steamgriddb.com/api/v2/logos/game/\(gameId)"
        guard let url = URL(string: endpoint) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let result = try JSONDecoder().decode(MediaResponse.self, from: data)
            guard let items = result.data, !items.isEmpty else { return nil }
            // Prefer PNG format for transparency
            let best = items.first { $0.mime?.contains("png") == true } ?? items.first
            guard let bestUrl = best?.url else { return nil }
            return URL(string: bestUrl)
        } catch {
            return nil
        }
    }

    public func fetchHeroURL(gameName: String, apiKey: String) async -> URL? {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let gameId = await findGameId(gameName: gameName, apiKey: apiKey) else { return nil }

        let endpoint = "https://www.steamgriddb.com/api/v2/heroes/game/\(gameId)"
        guard let url = URL(string: endpoint) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let result = try JSONDecoder().decode(MediaResponse.self, from: data)
            guard let items = result.data, !items.isEmpty else { return nil }
            // Prefer 1920x1080 or higher
            let sorted = items.sorted { ($0.width ?? 0) > ($1.width ?? 0) }
            guard let bestUrl = sorted.first?.url else { return nil }
            return URL(string: bestUrl)
        } catch {
            return nil
        }
    }

    public func fetchSquareGridURL(gameName: String, apiKey: String) async -> URL? {
        if case .found(let url) = await lookupSquareGrid(gameName: gameName, apiKey: apiKey) { return url }
        return nil
    }

    /// Distinguishes a definite empty answer (`.noGrid`) from any failure.
    public func lookupSquareGrid(gameName: String, apiKey: String) async -> SquareGridLookup {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .failed }
        let clean = cleanGameName(gameName)
        guard let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let searchURL = URL(string: "https://www.steamgriddb.com/api/v2/search/autocomplete/\(encoded)")
        else { return .failed }

        do {
            let search = try await get(searchURL, key: key)
            let found = try JSONDecoder().decode(AutocompleteResponse.self, from: search)
            guard let gameId = found.data?.first?.id else { return .noGrid }

            guard let gridURL = URL(string: "https://www.steamgriddb.com/api/v2/grids/game/\(gameId)?dimensions=512x512,1024x1024")
            else { return .failed }
            let data = try await get(gridURL, key: key)
            let result = try JSONDecoder().decode(MediaResponse.self, from: data)
            guard let items = result.data, !items.isEmpty else { return .noGrid }
            let pngs = items.filter { $0.mime?.contains("png") == true }
            let pool = pngs.isEmpty ? items : pngs
            guard let best = pool.max(by: { ($0.width ?? 0) < ($1.width ?? 0) }),
                  let url = URL(string: best.url) else { return .failed }
            return .found(url)
        } catch {
            return .failed
        }
    }

    private func get(_ url: URL, key: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func findGameId(gameName: String, apiKey: String) async -> Int? {
        let clean = cleanGameName(gameName)
        guard let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://www.steamgriddb.com/api/v2/search/autocomplete/\(encoded)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let result = try JSONDecoder().decode(AutocompleteResponse.self, from: data)
            return result.data?.first?.id
        } catch {
            return nil
        }
    }

    private func cleanGameName(_ name: String) -> String {
        var clean = name
        // Strip ™, ®, ©
        clean = clean.replacingOccurrences(of: "™", with: "")
        clean = clean.replacingOccurrences(of: "®", with: "")
        clean = clean.replacingOccurrences(of: "©", with: "")
        // Strip bracketed text like [0100...], (USA), etc.
        if let regex = try? NSRegularExpression(pattern: #"(\[[^\]]*\]|\([^\)]*\))"#) {
            clean = regex.stringByReplacingMatches(in: clean, range: NSRange(clean.startIndex..., in: clean), withTemplate: "")
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
