import Foundation

/// Splits a byte stream into lines on \n or \r: progress meters redraw with \r.
public struct LineBuffer {
    private var pending = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let index = pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let line = String(decoding: pending[pending.startIndex..<index], as: UTF8.self)
            pending.removeSubrange(pending.startIndex...index)
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }

    public mutating func finish() -> [String] {
        defer { pending.removeAll() }
        let line = String(decoding: pending, as: UTF8.self)
        return line.isEmpty ? [] : [line]
    }
}
