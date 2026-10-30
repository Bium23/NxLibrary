import Foundation

/// A long store description cut for Spotlight's page: whole paragraphs while
/// they fit, else whole sentences, else whole words with an ellipsis.
public struct DescriptionExcerpt: Equatable, Sendable {
    public let text: String
    /// Something was left out; the page offers Read more.
    public let truncated: Bool

    public init(text: String, truncated: Bool) {
        self.text = text
        self.truncated = truncated
    }

    public static func make(_ text: String, limit: Int) -> DescriptionExcerpt {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > limit else { return DescriptionExcerpt(text: text, truncated: false) }
        let enough = limit / 3

        var kept = ""
        for paragraph in text.components(separatedBy: "\n\n").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        where !paragraph.isEmpty {
            let next = kept.isEmpty ? paragraph : kept + "\n\n" + paragraph
            guard next.count <= limit else { break }
            kept = next
        }
        if kept.count >= enough { return DescriptionExcerpt(text: kept, truncated: true) }

        let head = String(text.prefix(limit))
        if let end = head.lastIndex(where: { ".!?。".contains($0) }), head.distance(from: head.startIndex, to: end) >= enough {
            return DescriptionExcerpt(text: String(head[...end]), truncated: true)
        }
        let words = head.lastIndex(of: " ").map { String(head[..<$0]) } ?? head
        return DescriptionExcerpt(text: words.trimmingCharacters(in: .whitespacesAndNewlines) + "…", truncated: true)
    }
}

/// Where Spotlight's page rests for Build & Sources and More like this. Build &
/// Sources brings About this game up to `top`, More like this comes up to `top`,
/// but neither scrolls past the page's end resting `bottomInset` above the
/// window's bottom; neither rises above the pills' shift (`first`). Positions
/// are from the page's top, in points.
public enum SpotlightPageScroll {
    public static func resting(first: CGFloat, aboutTop: CGFloat, moreTop: CGFloat?, pageBottom: CGFloat,
                               top: CGFloat, viewport: CGFloat, bottomInset: CGFloat) -> (actions: CGFloat, more: CGFloat) {
        let end = viewport - bottomInset - pageBottom
        let actions = min(first, max(top - aboutTop, end))
        guard let moreTop else { return (actions, actions) }
        return (actions, min(actions, max(top - moreTop, end)))
    }
}
