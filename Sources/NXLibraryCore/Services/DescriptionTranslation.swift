import CryptoKit
import Foundation
import NaturalLanguage

/// The language a description is written in, read on this Mac with NaturalLanguage. It decides whether
/// About this game offers Translate, for every source alike: a store text, a database pick or the player's own.
public enum TextLanguage {
    /// Shorter texts are too uncertain to name a language.
    static let minimumLength = 40
    static let minimumConfidence = 0.6

    /// A BCP 47 tag ("en", "it", "zh-Hans"), or nil when the text is short or no language clearly leads.
    public static func detect(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumLength else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              language != .undetermined, confidence >= minimumConfidence else { return nil }
        return language.rawValue
    }

    /// Whether a text in `tag` already reads in `language`. Languages compare by their base code (pt is pt-BR);
    /// Chinese compares by script too, so Traditional text is offered to a Simplified reader.
    public static func matches(_ tag: String, _ language: AppLanguage) -> Bool {
        let base = { (value: String) in value.split(separator: "-").first.map(String.init) ?? value }
        if base(language.rawValue) == "zh" { return tag == "zh-Hans" || tag == "zh" }
        return base(tag) == base(language.rawValue)
    }

    /// The language a Translate button would translate from, or nil when the text needs none for `language`.
    public static func translationSource(for text: String, into language: AppLanguage) -> String? {
        guard language != .automatic, let tag = detect(text), !matches(tag, language) else { return nil }
        return tag
    }
}

/// Descriptions translated on this Mac, one file per text and target language. The key is a hash of the exact
/// text, so a new store text or a changed pick never shows an old translation, and nothing needs clearing.
public struct DescriptionTranslationStore {
    private struct Entry: Codable {
        var version = 1
        var source: String
        var translation: String
        var translatedAt: Date
    }

    public let directory: URL

    public init(directory: URL = AppData.cacheRoot.appendingPathComponent("translations")) {
        self.directory = directory
    }

    public static func key(for text: String, into language: AppLanguage) -> String {
        let digest = SHA256.hash(data: Data((language.rawValue + "\n" + text).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func fileURL(for text: String, into language: AppLanguage) -> URL {
        directory.appendingPathComponent(language.rawValue, isDirectory: true)
            .appendingPathComponent(Self.key(for: text, into: language) + ".json")
    }

    public func translation(of text: String, into language: AppLanguage) -> String? {
        guard let data = try? Data(contentsOf: fileURL(for: text, into: language)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              !entry.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return entry.translation
    }

    public func save(_ translation: String, of text: String, from source: String, into language: AppLanguage) throws {
        let url = fileURL(for: text, into: language)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let entry = Entry(source: source, translation: translation, translatedAt: Date())
        try JSONEncoder().encode(entry).write(to: url, options: .atomic)
    }
}
