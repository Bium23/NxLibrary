import Foundation

public struct UpstreamCommit: Codable, Equatable, Identifiable {
    public var sha: String
    public var author: String
    public var date: String
    public var subject: String

    public var id: String { sha }
    public var shortSha: String { String(sha.prefix(7)) }

    public init(sha: String, author: String, date: String, subject: String) {
        self.sha = sha
        self.author = author
        self.date = date
        self.subject = subject
    }
}

public struct UpstreamStatus: Codable, Equatable {
    public var repository: String
    public var status: String
    public var baseCommit: String
    public var upstreamCommit: String
    public var aheadBy: Int
    public var behindBy: Int
    public var totalCommits: Int
    public var commits: [UpstreamCommit]
    public var compareURL: URL
    public var checkedAt: Date

    public var isUpToDate: Bool { aheadBy == 0 && behindBy == 0 }
    public var newCommitsCount: Int { max(aheadBy, totalCommits) }

    public init(repository: String, status: String, baseCommit: String,
                upstreamCommit: String, aheadBy: Int, behindBy: Int,
                totalCommits: Int, commits: [UpstreamCommit],
                compareURL: URL, checkedAt: Date) {
        self.repository = repository
        self.status = status
        self.baseCommit = baseCommit
        self.upstreamCommit = upstreamCommit
        self.aheadBy = aheadBy
        self.behindBy = behindBy
        self.totalCommits = totalCommits
        self.commits = commits
        self.compareURL = compareURL
        self.checkedAt = checkedAt
    }
}

public enum UpstreamCheckerError: Error, Equatable, LocalizedError {
    case invalidBase
    case invalidURL
    case http(Int, String?)
    case rateLimited(Date?)
    case decoding

    public var errorDescription: String? {
        switch self {
        case .invalidBase:
            return "The engine commit is not a valid hash."
        case .invalidURL:
            return "Could not build the GitHub API URL."
        case .http(let status, let message):
            return "GitHub returned status \(status)\(message.map { ": \($0)" } ?? ".")"
        case .rateLimited(let reset):
            if let reset {
                return "GitHub API rate limit reached. Try again after \(reset.formatted(date: .abbreviated, time: .shortened))."
            }
            return "GitHub API rate limit reached. Try again later."
        case .decoding:
            return "GitHub returned a response this app could not read."
        }
    }
}

public protocol UpstreamHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionUpstreamClient: UpstreamHTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

public final class UpstreamChecker {
    public static let repository = "seedds/nxnative"
    public static let branch = "main"

    private let client: UpstreamHTTPClient

    public init(client: UpstreamHTTPClient = URLSessionUpstreamClient()) {
        self.client = client
    }

    public func check(from baseCommit: String) async throws -> UpstreamStatus {
        let base = baseCommit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, base.allSatisfy({ $0.isHexDigit }) else {
            throw UpstreamCheckerError.invalidBase
        }
        guard let apiURL = URL(
            string: "https://api.github.com/repos/\(Self.repository)/compare/\(base)...\(Self.branch)"
        ) else {
            throw UpstreamCheckerError.invalidURL
        }

        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("NXLibrary/0.1", forHTTPHeaderField: "User-Agent")

        let (data, http) = try await client.data(for: request)
        let message = (try? JSONDecoder().decode(APIError.self, from: data))?.message

        if http.statusCode == 403 || http.statusCode == 429,
           http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" {
            let reset = http.value(forHTTPHeaderField: "x-ratelimit-reset")
                .flatMap(Double.init)
                .map { Date(timeIntervalSince1970: $0) }
            throw UpstreamCheckerError.rateLimited(reset)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UpstreamCheckerError.http(http.statusCode, message)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(ComparePayload.self, from: data) else {
            throw UpstreamCheckerError.decoding
        }

        let ahead = payload.aheadBy ?? 0
        let behind = payload.behindBy ?? 0
        let rawCommits = payload.commits ?? []
        let commits = rawCommits.reversed().prefix(100).map { item in
            let message = item.commit?.message ?? ""
            let subject = message.components(separatedBy: "\n").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return UpstreamCommit(
                sha: item.sha,
                author: item.commit?.author?.name ?? "unknown",
                date: item.commit?.author?.date ?? "",
                subject: subject.isEmpty ? "(no message)" : subject
            )
        }
        let upstream = rawCommits.last?.sha ?? payload.baseCommit?.sha ?? base
        guard let compareURL = URL(
            string: "https://github.com/\(Self.repository)/compare/\(base)...\(Self.branch)"
        ) else {
            throw UpstreamCheckerError.invalidURL
        }

        return UpstreamStatus(
            repository: Self.repository,
            status: payload.status ?? "unknown",
            baseCommit: payload.baseCommit?.sha ?? base,
            upstreamCommit: upstream,
            aheadBy: ahead,
            behindBy: behind,
            totalCommits: max(payload.totalCommits ?? ahead, ahead),
            commits: Array(commits),
            compareURL: compareURL,
            checkedAt: Date()
        )
    }
}

private struct ComparePayload: Decodable {
    let status: String?
    let aheadBy: Int?
    let behindBy: Int?
    let totalCommits: Int?
    let baseCommit: CommitRef?
    let commits: [CommitPayload]?
}

private struct CommitRef: Decodable {
    let sha: String
}

private struct CommitPayload: Decodable {
    let sha: String
    let commit: CommitDetail?
}

private struct CommitDetail: Decodable {
    let author: CommitAuthor?
    let message: String?
}

private struct CommitAuthor: Decodable {
    let name: String?
    let date: String?
}

private struct APIError: Decodable {
    let message: String?
}
