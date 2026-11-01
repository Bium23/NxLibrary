import Foundation
import Darwin

public struct KeySummary: Equatable {
    public var hasHeaderKey: Bool
    public var applicationKeyGenerations: [Int]

    public init(hasHeaderKey: Bool, applicationKeyGenerations: [Int]) {
        self.hasHeaderKey = hasHeaderKey
        self.applicationKeyGenerations = applicationKeyGenerations
    }
}

public enum KeyStoreError: Error, LocalizedError {
    case unreadable
    case missingHeaderKey
    case invalidLine(Int)
    public var errorDescription: String? {
        switch self {
        case .unreadable: return "The key file could not be read."
        case .missingHeaderKey: return "The key file has no header_key."
        case .invalidLine(let line): return "Invalid key line number \(line)."
        }
    }
}

public final class KeyStore {
    public let keyURL: URL
    private let fm: FileManager
    /// Publication is one same-directory rename: failure leaves the existing key in place.
    internal var publish: (URL, URL) throws -> Void = { incoming, destination in
        guard rename(incoming.path, destination.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    public init(directory: URL, fileManager: FileManager = .default) {
        self.fm = fileManager
        self.keyURL = directory.appendingPathComponent("prod.keys")
    }

    public func validate(at url: URL) throws -> KeySummary {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw KeyStoreError.unreadable
        }
        var hasHeader = false
        var generations: [Int] = []
        for (index, raw) in text.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2, !parts[1].isEmpty else {
                throw KeyStoreError.invalidLine(index + 1)
            }
            if parts[0] == "header_key" { hasHeader = true }
            if parts[0].hasPrefix("key_area_key_application_"),
               let n = Int(parts[0].suffix(2), radix: 16) {
                generations.append(n)
            }
        }
        guard hasHeader else { throw KeyStoreError.missingHeaderKey }
        return KeySummary(hasHeaderKey: true,
                          applicationKeyGenerations: Array(Set(generations)).sorted())
    }

    @discardableResult
    public func importKey(from source: URL) throws -> KeySummary {
        let summary = try validate(at: source)
        try fm.createDirectory(at: keyURL.deletingLastPathComponent(),
                               withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let data = try Data(contentsOf: source)
        let tmp = keyURL.deletingLastPathComponent()
            .appendingPathComponent(".prod.keys-\(UUID()).tmp")
        defer { try? fm.removeItem(at: tmp) }
        try data.write(to: tmp, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
        try publish(tmp, keyURL)
        return summary
    }
}
