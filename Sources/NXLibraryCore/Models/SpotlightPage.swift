import Foundation

/// A long store description cut for Spotlight's page: at least `minLines`
/// lines (as tall as the column beside it), ending on a whole sentence; a
/// run-on sentence is cut at a word with an ellipsis. Lines are estimated from
/// `charsPerLine`, and every line break starts a line.
public struct DescriptionExcerpt: Equatable, Sendable {
    public let text: String
    /// Something was left out; the page offers Read more.
    public let truncated: Bool

    public init(text: String, truncated: Bool) {
        self.text = text
        self.truncated = truncated
    }

    public static func make(_ text: String, minLines: Int, charsPerLine: Int) -> DescriptionExcerpt {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let perLine = max(charsPerLine, 1)
        guard lines(text, perLine) > minLines else { return DescriptionExcerpt(text: text, truncated: false) }

        let chars = Array(text)
        for end in chars.indices where ".!?。".contains(chars[end]) && (end + 1 == chars.count || chars[end + 1].isWhitespace) {
            let head = String(chars[...end])
            let used = lines(head, perLine)
            guard used >= minLines else { continue }
            // A sentence running far past the column: cut at a word instead.
            guard used <= minLines + 2 else { break }
            let rest = String(chars[(end + 1)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            // A last line left over is shown rather than hidden behind Read more.
            if lines(rest, perLine) <= 1 { return DescriptionExcerpt(text: text, truncated: false) }
            return DescriptionExcerpt(text: head, truncated: true)
        }
        let head = String(text.prefix(minLines * perLine))
        let words = head.lastIndex(of: " ").map { String(head[..<$0]) } ?? head
        return DescriptionExcerpt(text: words.trimmingCharacters(in: .whitespacesAndNewlines) + "…", truncated: true)
    }

    /// Estimated lines: each line of the text wraps every `perLine` characters; a blank one is a line.
    static func lines(_ text: String, _ perLine: Int) -> Int {
        text.components(separatedBy: "\n").reduce(0) { $0 + max(1, ($1.count + perLine - 1) / perLine) }
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

public extension SpotlightPageScroll {
    /// `offset`, or further up until `bottom` (from the page's top) rests
    /// `bottomInset` above the window's bottom: Read more under a long description.
    static func revealing(_ offset: CGFloat, bottom: CGFloat, viewport: CGFloat, bottomInset: CGFloat) -> CGFloat {
        min(offset, viewport - bottomInset - bottom)
    }
}
