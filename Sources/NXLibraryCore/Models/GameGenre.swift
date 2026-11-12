import Foundation

/// Translate known catalog genres at presentation time. Raw metadata and personal choices stay untouched.
public enum GameGenre {
    public static func title(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if L10n.context.language == .english { return trimmed }
        let normalized = trimmed.lowercased().replacingOccurrences(of: "-", with: " ")
        let known: String
        switch normalized {
        case "action": known = "Action"
        case "adventure": known = "Adventure"
        case "action adventure": known = "Action-adventure"
        case "role playing", "roleplaying", "rpg": known = "Role-playing"
        case "puzzle": known = "Puzzle"
        case "platformer", "platform", "platforming": known = "Platformer"
        case "racing": known = "Racing"
        case "sports", "sport": known = "Sports"
        case "simulation", "simulator": known = "Simulation"
        case "strategy": known = "Strategy"
        case "fighting", "fighter": known = "Fighting"
        case "shooter", "shooting": known = "Shooter"
        case "arcade": known = "Arcade"
        case "party": known = "Party"
        case "music", "rhythm", "music/rhythm": known = "Music"
        case "board game", "board games", "board": known = "Board game"
        case "card game", "card games": known = "Card game"
        case "education", "educational", "study": known = "Education"
        case "fitness", "training": known = "Fitness"
        case "communication": known = "Communication"
        case "lifestyle", "practical": known = "Lifestyle"
        case "utility", "utilities": known = "Utility"
        default: return trimmed
        }
        return L10n.text("Game genre: " + known)
    }

    public static func list(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        return raw.compactMap { value in
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.caseInsensitiveCompare("Other") != .orderedSame else { return nil }
            let localized = title(value)
            return seen.insert(localized.lowercased()).inserted ? localized : nil
        }
    }
}
