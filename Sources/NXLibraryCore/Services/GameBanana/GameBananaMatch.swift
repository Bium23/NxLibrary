import Foundation

/// Finding a game's GameBanana page by name: GameBanana has no Switch title IDs, and lists some games once per
/// platform with a suffix ("… (Switch)", "… (WiiU)").
public enum GameBananaMatch {
    public enum Decision: Equatable {
        case matched(GameBananaGame)
        /// Not sure: ask "Is this the right game?" with these (at most 5, other platforms last).
        case ask([GameBananaGame])
        case none
    }

    static let maxCandidates = 5
    private static let switchSuffixes: Set<String> = ["switch", "nintendo switch", "ns", "switch 2", "nintendo switch 2"]

    /// Lowercase, no accents or ™®©, "&" as "and", punctuation as single spaces.
    public static func normalized(_ name: String) -> String {
        var text = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
        for mark in ["™", "®", "©"] { text = text.replacingOccurrences(of: mark, with: "") }
        text = text.replacingOccurrences(of: "&", with: " and ")
        let words = text.unicodeScalars.split { !CharacterSet.alphanumerics.contains($0) }.map { String(String.UnicodeScalarView($0)) }
        return words.joined(separator: " ")
    }

    public static func decide(names: [String], results: [GameBananaGame]) -> Decision {
        guard !results.isEmpty else { return .none }
        let wanted = Set(names.map(normalized).filter { !$0.isEmpty })
        let parsed = results.map { ($0, split($0.name)) }
        let exact = parsed.filter { wanted.contains($0.1.base) && $0.1.platform != .other }
        if let pick = exact.first(where: { $0.1.platform == .switch }) ?? exact.first { return .matched(pick.0) }
        let ordered = parsed.filter { $0.1.platform != .other } + parsed.filter { $0.1.platform == .other }
        return .ask(Array(ordered.prefix(maxCandidates).map(\.0)))
    }

    private enum Platform { case none, `switch`, other }

    private static func split(_ name: String) -> (base: String, platform: Platform) {
        guard let range = name.range(of: "\\s*\\(([^()]*)\\)\\s*$", options: .regularExpression) else {
            return (normalized(name), .none)
        }
        let suffix = normalized(String(name[range]))
        return (normalized(String(name[..<range.lowerBound])), switchSuffixes.contains(suffix) ? .switch : .other)
    }
}

/// The player's answer for one game.
public enum GameBananaChoice: Codable, Equatable, Sendable {
    case game(id: Int, name: String, profileURL: URL)
    /// "None of these": the band shows "No GameBanana page found" until the player picks a game.
    case noPage
}

/// The remembered GameBanana page of each game, by title ID, in one JSON file.
public struct GameBananaMatchStore {
    public let file: URL

    public init(file: URL) { self.file = file }

    public func choice(titleID: String) -> GameBananaChoice? { load()[titleID.uppercased()] }

    /// Nil forgets the choice.
    public func set(_ choice: GameBananaChoice?, titleID: String) throws {
        var all = load()
        all[titleID.uppercased()] = choice
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(all).write(to: file, options: .atomic)
    }

    private func load() -> [String: GameBananaChoice] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([String: GameBananaChoice].self, from: data)) ?? [:]
    }
}
