import Foundation

/// How far an install has got: a fraction for the card's bar (nil: still going,
/// no number to show) and a few words for the panel.
public struct InstallProgress: Equatable {
    public var fraction: Double?
    public var label: String

    public init(fraction: Double?, label: String) {
        self.fraction = fraction
        self.label = label
    }

    /// git clone/fetch --progress phases, mapped onto one bar; Receiving objects is most of the wait.
    private static let gitPhases: [(name: String, from: Double, to: Double)] = [
        ("Counting objects", 0, 0.05), ("Compressing objects", 0.05, 0.1), ("Receiving objects", 0.1, 0.85),
        ("Resolving deltas", 0.85, 0.95), ("Updating files", 0.95, 1)]

    public static func git(_ line: String) -> InstallProgress? {
        for phase in gitPhases {
            guard let range = line.range(of: phase.name + ":") else { continue }
            guard let percent = percent(String(line[range.upperBound...])) else { return nil }
            let whole = Int((percent * 100).rounded())
            return InstallProgress(fraction: phase.from + (phase.to - phase.from) * percent,
                                   label: "\(phase.name) \(whole)%")
        }
        return nil
    }

    /// The last "12" or "12.5" followed by %, as a fraction; nil when there is none in 0…100.
    public static func percent(_ line: String) -> Double? {
        var found: Double?
        var number = ""
        for character in line {
            if character.isNumber || (character == "." && !number.isEmpty) {
                number.append(character)
            } else {
                if character == "%", let value = Double(number) { found = value }
                number = ""
            }
        }
        guard let found, (0...100).contains(found) else { return nil }
        return found / 100
    }

    public static func bytes(done: Int64, total: Int64) -> InstallProgress {
        let mb = { (value: Int64) in Int((Double(value) / 1_048_576).rounded()) }
        guard total > 0 else { return InstallProgress(fraction: nil, label: L10n.format("%@ MB", [String(describing: (mb(done)))])) }
        return InstallProgress(fraction: min(1, Double(done) / Double(total)), label: L10n.format("%@ of %@ MB", [String(describing: (mb(done))), String(describing: (mb(total)))]))
    }
}

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
