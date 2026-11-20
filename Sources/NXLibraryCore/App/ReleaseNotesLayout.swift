import Foundation

/// Release notes as the update dialog lays them out: one entry per line of the notes, so the dialog's scrolling
/// (by line index) keeps working, each read as a section heading, a list item or plain text.
public enum ReleaseNotesLayout {
    public enum Kind: Equatable, Sendable {
        case heading, item, text, blank
    }

    public struct Line: Equatable, Sendable {
        public let kind: Kind
        /// The words shown, without the Markdown marker ("### ", "- ").
        public let text: String
    }

    public static func lines(_ notes: String) -> [Line] {
        notes.components(separatedBy: "\n").map(line)
    }

    static func line(_ raw: String) -> Line {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return Line(kind: .blank, text: "") }
        if trimmed.hasPrefix("#") {
            return Line(kind: .heading, text: String(trimmed.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces))
        }
        for marker in ["- ", "* ", "• "] where trimmed.hasPrefix(marker) {
            return Line(kind: .item, text: String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces))
        }
        return Line(kind: .text, text: trimmed)
    }
}
