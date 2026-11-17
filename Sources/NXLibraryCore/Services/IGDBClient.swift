import Foundation

/// Shared IGDB authentication and bounded serial requests; provider data stays in its own services.
actor IGDBClient {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    static let shared = IGDBClient()
    private let transport: Transport
    private struct Token { let owner: String; let value: String; let expires: Date }
    private var token: Token?
    private var lastRequest = Date.distantPast
    private var tail: Task<Void, Never>?
    private var jobs: [UUID: Task<Data, Error>] = [:]

    init(transport: @escaping Transport = { try await IGDBClient.download($0) }) {
        self.transport = transport
    }
    func resetToken() { token = nil }

    func request(_ endpoint: String, body: String, credentials: IGDBCredentials, renewToken: Bool = false) async throws -> Data {
        guard ["games", "external_games"].contains(endpoint), body.utf8.count <= 16_384 else { throw IGDBError.invalidResponse }
        guard jobs.count < 8 else { throw IGDBError.rateLimited }
        let id = UUID(), prior = tail
        let task = Task {
            await prior?.value
            try Task.checkCancellation()
            if renewToken { self.token = nil }
            return try await self.api(endpoint, body: body, credentials: credentials)
        }
        jobs[id] = task
        tail = Task { _ = try? await task.value }
        defer { jobs[id] = nil }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }
    private func accessToken(_ credentials: IGDBCredentials) async throws -> String {
        if let token, token.owner == credentials.fingerprint, token.expires > Date() { return token.value }
        var form = URLComponents()
        form.queryItems = [.init(name: "client_id", value: credentials.clientID), .init(name: "client_secret", value: credentials.clientSecret),
                           .init(name: "grant_type", value: "client_credentials")]
        var request = URLRequest(url: URL(string: "https://id.twitch.tv/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await send(request)
        guard response.statusCode == 200 else {
            throw [400, 401, 403].contains(response.statusCode) ? IGDBError.rejected : IGDBError.unreachable
        }
        struct Wire: Decodable { let access_token: String; let expires_in: Double; let token_type: String }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data), wire.token_type.lowercased() == "bearer",
              wire.expires_in.isFinite, wire.expires_in > 60, wire.access_token.count <= 2048,
              !wire.access_token.isEmpty, wire.access_token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") })
        else { throw IGDBError.invalidResponse }
        try Task.checkCancellation()
        token = Token(owner: credentials.fingerprint, value: wire.access_token,
                      expires: Date().addingTimeInterval(min(wire.expires_in, 31_622_400) - 60))
        return wire.access_token
    }
    private func api(_ endpoint: String, body: String, credentials: IGDBCredentials) async throws -> Data {
        for attempt in 0...1 {
            let access = try await accessToken(credentials)
            var request = URLRequest(url: URL(string: "https://api.igdb.com/v4/\(endpoint)")!)
            request.httpMethod = "POST"; request.httpBody = Data(body.utf8)
            request.setValue(credentials.clientID, forHTTPHeaderField: "Client-ID")
            request.setValue("Bearer " + access, forHTTPHeaderField: "Authorization")
            request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await send(request)
            if response.statusCode == 401, attempt == 0 { token = nil; continue }
            guard (200..<300).contains(response.statusCode) else {
                if response.statusCode == 429 { throw IGDBError.rateLimited }
                throw [401,403].contains(response.statusCode) ? IGDBError.rejected : IGDBError.unreachable
            }
            return data
        }
        throw IGDBError.rejected
    }
    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        let delay = 0.26 - Date().timeIntervalSince(lastRequest)
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        try Task.checkCancellation()
        lastRequest = Date()
        do {
            let result = try await transport(request)
            try Task.checkCancellation()
            guard result.0.count <= 2_097_152, result.1.url == request.url else { throw IGDBError.invalidResponse }
            return result
        } catch is CancellationError { throw CancellationError() }
        catch let error as IGDBError { throw error }
        catch { throw IGDBError.unreachable }
    }
    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 20; config.timeoutIntervalForRequest = 12
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil
        return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }()
    public static func download(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, url.query == nil, request.httpMethod == "POST",
              (url.host == "id.twitch.tv" && url.path == "/oauth2/token") ||
                (url.host == "api.igdb.com" && ["/v4/games", "/v4/external_games"].contains(url.path)) else { throw IGDBError.unreachable }
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppIdentity.userAgent(), forHTTPHeaderField: "User-Agent")
        let data: Data, response: URLResponse
        do { (data, response) = try await BoundedDownload.data(for: request, session: session, limit: 2_097_152) }
        catch let error as URLError where error.code == .dataLengthExceedsMaximum { throw IGDBError.invalidResponse }
        guard let http = response as? HTTPURLResponse, http.url == url else { throw IGDBError.invalidResponse }
        return (data, http)
    }
}
