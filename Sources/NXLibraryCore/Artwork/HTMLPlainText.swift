import Foundation

/// A store or mod description as plain text: line breaks and list items kept, every other tag dropped, entities
/// decoded. A string pass only: nothing in the description is ever loaded.
public enum HTMLPlainText {
    public static func text(fromHTML html: String) -> String {
        var text = html
        let rules: [(String, String)] = [
            ("<li[^>]*>", "\n• "),
            ("<br\\s*/?>|</p>|</div>|</li>|</h[1-6]>", "\n"),
            ("<[^>]*>", ""),
        ]
        for (pattern, replacement) in rules {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }
        text = decodeEntities(text)
        let lines = text.components(separatedBy: "\n").map { line -> String in
            var line = line
            while line.last == " " || line.last == "\t" { line.removeLast() }
            return line
        }
        text = lines.joined(separator: "\n")
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ text: String) -> String {
        var text = text
        for (entity, value) in [("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"),
                                ("&nbsp;", " "), ("&#160;", " ")] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let whole = Range(match.range, in: text), let digits = Range(match.range(at: 2), in: text) else { continue }
                let hex = match.range(at: 1).length > 0
                if let code = UInt32(text[digits], radix: hex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                    text.replaceSubrange(whole, with: String(Character(scalar)))
                }
            }
        }
        return text.replacingOccurrences(of: "&amp;", with: "&")
    }
}
