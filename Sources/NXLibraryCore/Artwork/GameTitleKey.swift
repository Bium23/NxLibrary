import Foundation

/// A game title as words to compare: lower case, without ™ ® ©, "&" read as "and", punctuation dropped. Online
/// artwork searches and GameTDB matches compare names this way.
public enum GameTitleKey {
    public static func normalize(_ name: String) -> String {
        var text = name.lowercased()
        for mark in ["™", "®", "©"] { text = text.replacingOccurrences(of: mark, with: "") }
        text = text.replacingOccurrences(of: "&", with: " and ")
        let words = text.split { !($0.isLetter || $0.isNumber) }
        return words.joined(separator: " ")
    }
}
