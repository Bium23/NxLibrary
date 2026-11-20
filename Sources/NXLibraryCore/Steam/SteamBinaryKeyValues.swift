import Foundation

/// Steam's binary KeyValues (the `appcache/stats/*.bin` files), read into the same entries as the text format.
/// Each entry is a type byte, a NUL-terminated key and a value: 0 a subtree ending at 8, 1 a NUL-terminated string,
/// 2, 4 and 6 an int32, 3 a float32, 7 a uint64, all little-endian. Numbers become their decimal text. Every level,
/// the top one too, ends at 8 (Steam's files do). Anything else, or data that ends before that, is malformed.
public enum SteamBinaryKeyValues {
    public static let maximumBytes = 8 * 1024 * 1024

    public static func parse(_ data: Data, maximumDepth: Int = 32, maximumEntries: Int = 200_000) throws -> [KeyValuesEntry] {
        guard data.count <= maximumBytes else { throw KeyValuesError.limitExceeded }
        var cursor = Cursor(bytes: Array(data), maximumDepth: maximumDepth, maximumEntries: maximumEntries)
        return try cursor.object(depth: 0)
    }

    private struct Cursor {
        let bytes: [UInt8]
        let maximumDepth: Int
        let maximumEntries: Int
        var offset = 0
        var count = 0

        mutating func object(depth: Int) throws -> [KeyValuesEntry] {
            guard depth <= maximumDepth else { throw KeyValuesError.limitExceeded }
            var entries: [KeyValuesEntry] = []
            while true {
                // Every level, the top one too, ends with its terminator: data that stops before it is a file
                // cut while Steam wrote it, never a shorter file (an empty stats file would read as no unlocks).
                guard offset < bytes.count else { throw KeyValuesError.malformed }
                let type = bytes[offset]
                offset += 1
                if type == 8 { return entries }
                count += 1
                guard count <= maximumEntries else { throw KeyValuesError.limitExceeded }
                let key = try string()
                let value: KeyValuesValue
                switch type {
                case 0: value = .object(try object(depth: depth + 1))
                case 1: value = .string(try string())
                case 2, 4, 6: value = .string(String(Int32(bitPattern: UInt32(try integer(4)))))
                case 3: value = .string(String(Float(bitPattern: UInt32(try integer(4)))))
                case 7: value = .string(String(try integer(8)))
                default: throw KeyValuesError.malformed
                }
                entries.append(KeyValuesEntry(key: key, value: value))
            }
        }

        private mutating func string() throws -> String {
            guard let end = bytes[offset...].firstIndex(of: 0) else { throw KeyValuesError.malformed }
            defer { offset = end + 1 }
            return String(decoding: bytes[offset..<end], as: UTF8.self)
        }

        private mutating func integer(_ size: Int) throws -> UInt64 {
            guard offset + size <= bytes.count else { throw KeyValuesError.malformed }
            var value: UInt64 = 0
            for index in 0..<size { value |= UInt64(bytes[offset + index]) << (8 * index) }
            offset += size
            return value
        }
    }
}
