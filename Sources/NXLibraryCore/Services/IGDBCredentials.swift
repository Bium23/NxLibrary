import Foundation
import CryptoKit

/// The player's own Twitch application credentials; never bundled, logged or put in settings.
public struct IGDBCredentials: Equatable, Codable, Sendable {
    public let clientID: String
    public let clientSecret: String
    public init?(clientID: String, clientSecret: String) {
        func normalized(_ text: String) -> String? {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return (8...128).contains(value.count) && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } ? value : nil
        }
        guard let id = normalized(clientID), let secret = normalized(clientSecret) else { return nil }
        self.clientID = id; self.clientSecret = secret
    }
    /// Only a digest names in-flight work. Neither credentials nor tokens appear in filenames.
    var fingerprint: String { Self.digest(clientID + ":" + clientSecret) }
    static func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
}

public struct IGDBCredentialsStore {
    public let url: URL
    public init(url: URL = AppData.supportRoot.appendingPathComponent("credentials/igdb.json")) { self.url = url }
    public func load() -> IGDBCredentials? {
        guard let data = try? InstallationFileSnapshot.read(at: url, maximumBytes: 4096).data,
              let value = try? JSONDecoder().decode(IGDBCredentials.self, from: data) else { return nil }
        return IGDBCredentials(clientID: value.clientID, clientSecret: value.clientSecret)
    }
    public func save(_ value: IGDBCredentials) throws {
        let fm = FileManager.default
        let temp = url.deletingLastPathComponent().appendingPathComponent(".igdb-" + UUID().uuidString)
        defer { try? fm.removeItem(at: temp) }
        do {
            let folder = url.deletingLastPathComponent()
            try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            // Creation applies the mode only to a new folder; an existing one is made private too.
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
            let data = try JSONEncoder().encode(value)
            guard fm.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]),
                  rename(temp.path, url.path) == 0 else { throw IGDBError.notSaved }
        } catch { throw IGDBError.notSaved }
    }
    public func remove() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { try FileManager.default.removeItem(at: url) } catch { throw IGDBError.notSaved }
    }
}

public enum IGDBError: Error, LocalizedError, Equatable {
    case invalidCredentials, rejected, unreachable, rateLimited, invalidResponse, notSaved
    public var errorDescription: String? {
        switch self {
        case .invalidCredentials: return L10n.text("Enter the Client ID and Client Secret from your Twitch developer application.")
        case .rejected: return L10n.text("IGDB did not accept these credentials. Check the Client ID and Client Secret.")
        case .unreachable, .invalidResponse: return L10n.text("IGDB could not be reached. Check the connection and try again.")
        case .rateLimited: return L10n.text("IGDB is busy. Wait a moment and try again.")
        case .notSaved: return L10n.text("IGDB credentials could not be saved on this Mac.")
        }
    }
}
