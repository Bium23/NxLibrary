import Foundation

public enum KeyValuesError: Error, Equatable {
    case malformed, limitExceeded
    case duplicateField(String), unsupportedDirective(String)
}

public enum KeyValuesValue: Equatable, Sendable {
    case string(String)
    case object([KeyValuesEntry])
}

public struct KeyValuesEntry: Equatable, Sendable {
    public let key: String
    public let value: KeyValuesValue
}

public extension Array where Element == KeyValuesEntry {
    /// The first matching key, regardless of its value's type. Later copies are not consulted.
    func firstValue(for key: String) -> KeyValuesValue? {
        matchingEntries(for: key).first?.value
    }

    /// The first matching string, skipping same-named values of another type (Steam achievement data).
    func firstString(for key: String) -> String? {
        for entry in matchingEntries(for: key) {
            if case .string(let value) = entry.value { return value }
        }
        return nil
    }

    /// The first matching object, skipping same-named values of another type (Steam achievement data).
    func firstObject(for key: String) -> [KeyValuesEntry]? {
        for entry in matchingEntries(for: key) {
            if case .object(let value) = entry.value { return value }
        }
        return nil
    }

    /// Missing is nil; duplicate keys of any type are ambiguous and fail.
    func uniqueValue(for key: String) throws -> KeyValuesValue? {
        var result: KeyValuesValue?
        for entry in matchingEntries(for: key) {
            guard result == nil else { throw KeyValuesError.duplicateField(key) }
            result = entry.value
        }
        return result
    }

    /// A single string or nil when absent; duplicates and a value of another type fail.
    func uniqueString(for key: String) throws -> String? {
        guard let value = try uniqueValue(for: key) else { return nil }
        guard case .string(let text) = value else { throw KeyValuesError.malformed }
        return text
    }

    private func matchingEntries(for key: String) -> LazyFilterSequence<[KeyValuesEntry]> {
        lazy.filter { $0.key.caseInsensitiveCompare(key) == .orderedSame }
    }
}

/// The bounded text subset used by Steam's local indexes and manifests.
/// Entries retain order and duplicates; unique lookups reject ambiguous fields.
/// Directives never cause filesystem access: a `#` key is refused, or with `rejectsDirectives`
/// off (for files that only hold data, such as `localconfig.vdf`) read as an ordinary key.
public struct KeyValuesDocument: Sendable {
    public let entries: [KeyValuesEntry]

    public init(text: String, maximumDepth: Int = 32, maximumEntries: Int = 20_000, rejectsDirectives: Bool = true) throws {
        guard text.utf8.count <= 8 * 1024 * 1024, maximumDepth >= 0, maximumEntries >= 0 else {
            throw KeyValuesError.limitExceeded
        }
        var reader = Reader(bytes: Array(text.utf8), maximumDepth: maximumDepth, maximumEntries: maximumEntries,
                            rejectsDirectives: rejectsDirectives)
        entries = try reader.object(depth: 0)
    }

    public func uniqueValue(for key: String) throws -> KeyValuesValue? {
        try entries.uniqueValue(for: key)
    }
}

private struct Reader {
    let bytes: [UInt8]
    let maximumDepth: Int
    let maximumEntries: Int
    let rejectsDirectives: Bool
    private var offset = 0
    private var count = 0

    init(bytes: [UInt8], maximumDepth: Int, maximumEntries: Int, rejectsDirectives: Bool) {
        self.bytes = bytes
        self.maximumDepth = maximumDepth
        self.maximumEntries = maximumEntries
        self.rejectsDirectives = rejectsDirectives
        if bytes.starts(with: [0xef, 0xbb, 0xbf]) { offset = 3 }
    }

    private enum Token { case scalar(String), open, close }

    mutating func object(depth: Int) throws -> [KeyValuesEntry] {
        var entries: [KeyValuesEntry] = []
        while let token = try readToken() {
            if case .close = token {
                guard depth > 0 else { throw KeyValuesError.malformed }
                return entries
            }
            guard case .scalar(let key) = token, !key.isEmpty else { throw KeyValuesError.malformed }
            guard !rejectsDirectives || !key.hasPrefix("#") else { throw KeyValuesError.unsupportedDirective(key) }
            guard count < maximumEntries else { throw KeyValuesError.limitExceeded }
            count += 1
            let value: KeyValuesValue
            switch try readToken() {
            case .scalar(let text): value = .string(text)
            case .open:
                guard depth < maximumDepth else { throw KeyValuesError.limitExceeded }
                value = .object(try object(depth: depth + 1))
            default: throw KeyValuesError.malformed
            }
            entries.append(KeyValuesEntry(key: key, value: value))
        }
        guard depth == 0 else { throw KeyValuesError.malformed }
        return entries
    }

    private mutating func readToken() throws -> Token? {
        skipTrivia()
        guard offset < bytes.count else { return nil }
        let first = bytes[offset]
        offset += 1
        if first == 123 { return .open }
        if first == 125 { return .close }
        if first == 34 { return .scalar(try quoted()) }
        guard first != 0 else { throw KeyValuesError.malformed }
        let start = offset - 1
        while offset < bytes.count {
            let byte = bytes[offset]
            if isWhitespace(byte) || byte == 123 || byte == 125 || isComment { break }
            guard byte != 0, byte != 34 else { throw KeyValuesError.malformed }
            offset += 1
        }
        return .scalar(String(decoding: bytes[start..<offset], as: UTF8.self))
    }

    private mutating func quoted() throws -> String {
        var result: [UInt8] = []
        while offset < bytes.count {
            let byte = bytes[offset]
            offset += 1
            if byte == 34 { return String(decoding: result, as: UTF8.self) }
            guard byte != 0 else { throw KeyValuesError.malformed }
            if byte == 92 {
                guard offset < bytes.count else { throw KeyValuesError.malformed }
                let escaped = bytes[offset]
                offset += 1
                switch escaped {
                case 34, 92: result.append(escaped)
                case 110: result.append(10)
                case 116: result.append(9)
                case 114: result.append(13)
                default: throw KeyValuesError.malformed
                }
            } else { result.append(byte) }
        }
        throw KeyValuesError.malformed
    }

    private var isComment: Bool {
        offset + 1 < bytes.count && bytes[offset] == 47 && bytes[offset + 1] == 47
    }

    private func isWhitespace(_ byte: UInt8) -> Bool { byte == 32 || (9...13).contains(byte) }

    private mutating func skipTrivia() {
        while offset < bytes.count {
            if isWhitespace(bytes[offset]) { offset += 1 }
            else if isComment {
                while offset < bytes.count && bytes[offset] != 10 && bytes[offset] != 13 { offset += 1 }
            } else { return }
        }
    }
}
