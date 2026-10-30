import Foundation
import CryptoKit

public struct DotnetPackage: Equatable {
    public let version: String
    public let url: URL
    public let sha512: String
}

/// Microsoft's own installer for the .NET 10 SDK, found through its release
/// metadata and checked against the hash published there before it is opened.
public enum DotnetRelease {
    public static let metadataURL = URL(string: "https://builds.dotnet.microsoft.com/dotnet/release-metadata/10.0/releases.json")!

    public enum Failure: LocalizedError {
        case noPackage
        public var errorDescription: String? { "Microsoft's release list has no .NET 10 SDK installer for this Mac." }
    }

    private struct Metadata: Decodable {
        let latestSDK: String?
        let releases: [Release]?
        enum CodingKeys: String, CodingKey { case latestSDK = "latest-sdk", releases }
    }
    private struct Release: Decodable { let sdk: SDK?; let sdks: [SDK]? }
    private struct SDK: Decodable { let version: String; let files: [File] }
    private struct File: Decodable { let rid: String?; let url: String; let hash: String }

    public static func latestSDKPackage(from json: Data) throws -> DotnetPackage {
        let metadata = try JSONDecoder().decode(Metadata.self, from: json)
        guard let latest = metadata.latestSDK else { throw Failure.noPackage }
        let sdks = (metadata.releases ?? []).flatMap { [$0.sdk].compactMap { $0 } + ($0.sdks ?? []) }
        guard let sdk = sdks.first(where: { $0.version == latest }),
              let file = sdk.files.first(where: { $0.rid == "osx-arm64" && $0.url.hasSuffix(".pkg") }),
              let url = URL(string: file.url) else { throw Failure.noPackage }
        return DotnetPackage(version: sdk.version, url: url, sha512: file.hash)
    }

    public static func verify(file: URL, sha512: String) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA512()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return hex == sha512.lowercased()
    }
}
