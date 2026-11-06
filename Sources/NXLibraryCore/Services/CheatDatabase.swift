import Foundation

/// The community cheat list the Cheats panel offers from: switch-cheats-db (HamletDuFromage), one JSON file per game
/// (`cheats/<title ID>.json`), keyed by build ID, each value one Atmosphère block (`[Name]` or `{Name}` and its
/// codes). It is fetched only when the player opens the panel, never bundled or kept in the repository. A cheat is
/// for one build exactly, so only the running build's cheats are ever offered.
public enum CheatDatabase {
    /// Credit shown with the offer.
    public static let name = "switch-cheats-db"
    /// A game's file is a few hundred kilobytes at most; anything far larger is not the list.
    public static let maxBytes = 4 * 1024 * 1024

    /// The game's file; nil for anything but a title ID (16 hex digits), so nothing else reaches the address.
    public static func url(titleID: String) -> URL? {
        guard titleID.count == 16, titleID.allSatisfy(\.isHexDigit) else { return nil }
        return URL(string: "https://raw.githubusercontent.com/HamletDuFromage/switch-cheats-db/master/cheats/"
                   + titleID.uppercased() + ".json")
    }

    /// The cheat file for `buildID`: its blocks in the database's own order, each ending in a blank line but the
    /// last; nil when the database has no block for that build. Values that are not a block are left out, so a loose
    /// line can never join the cheat before it.
    public static func cheatText(json: Data, buildID: String) -> String? {
        let build = buildID.uppercased()
        guard json.count <= maxBytes,
              let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let cheats = root[build] as? [String: Any] else { return nil }
        let blocks = cheats.compactMap { key, value -> (key: String, text: String)? in
            guard let text = value as? String else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = trimmed.first, first == "[" || first == "{" else { return nil }
            return (key, trimmed)
        }
        guard !blocks.isEmpty else { return nil }
        let order = keyOrder(in: json, build: build, keys: blocks.map(\.key))
        let sorted = blocks.sorted { a, b in
            let (x, y) = (order[a.key] ?? .max, order[b.key] ?? .max)
            return x != y ? x < y : a.key < b.key
        }
        return sorted.map(\.text).joined(separator: "\n\n") + "\n"
    }

    /// Where each key first appears after the build's own key in the raw text: JSON objects carry no order, the file
    /// does. A key not found sorts after the rest, by name.
    private static func keyOrder(in json: Data, build: String, keys: [String]) -> [String: Int] {
        let raw = String(decoding: json, as: UTF8.self)
        guard let start = raw.range(of: "\"\(build)\"")?.upperBound else { return [:] }
        var order: [String: Int] = [:]
        for key in keys {
            let quoted = ["\"\(key)\"", encoded(key)].compactMap { $0 }
            for needle in quoted {
                if let found = raw.range(of: needle, range: start..<raw.endIndex) {
                    order[key] = raw.distance(from: raw.startIndex, to: found.lowerBound)
                    break
                }
            }
        }
        return order
    }

    /// The key as JSON writes it (escapes included).
    private static func encoded(_ key: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [key], options: [.withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8), text.count >= 2 else { return nil }
        return String(text.dropFirst().dropLast())
    }
}
