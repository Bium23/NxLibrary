import XCTest
@testable import NXLibraryCore

final class DescriptionTranslationTests: XCTestCase {
    private let english = "Welcome to the Sinnoh region! Rich in nature and with the majestic Mt. Coronet at its centre."
    private let italian = "Benvenuti nella regione di Sinnoh! Ricca di natura e con il maestoso Monte Corona al centro."
    private let simplified = "欢迎来到神奥地区！这里自然资源丰富，以天冠山为中心，是一片流传着许多神话的土地，等待着你去探索。"
    private let traditional = "歡迎來到神奧地區！這裡自然資源豐富，以天冠山為中心，是一片流傳著許多神話的土地，等待著你去探索。"

    func testEnglishDescriptionIsOfferedToAnItalianReader() {
        XCTAssertEqual(TextLanguage.translationSource(for: english, into: .italian), "en")
    }

    func testDescriptionInTheAppLanguageNeedsNoTranslation() {
        XCTAssertNil(TextLanguage.translationSource(for: italian, into: .italian))
        XCTAssertNil(TextLanguage.translationSource(for: english, into: .english))
    }

    func testPortugueseMatchesBrazilianPortuguese() {
        XCTAssertTrue(TextLanguage.matches("pt", .portugueseBrazil))
    }

    func testChineseComparesScript() {
        XCTAssertNil(TextLanguage.translationSource(for: simplified, into: .chineseSimplified))
        XCTAssertEqual(TextLanguage.translationSource(for: traditional, into: .chineseSimplified), "zh-Hant")
        XCTAssertEqual(TextLanguage.translationSource(for: english, into: .chineseSimplified), "en")
    }

    func testShortTextIsNeverOffered() {
        XCTAssertNil(TextLanguage.translationSource(for: "Super Mario Odyssey", into: .italian))
        XCTAssertNil(TextLanguage.translationSource(for: "", into: .italian))
    }

    func testAutomaticNeverTranslates() {
        XCTAssertNil(TextLanguage.translationSource(for: english, into: .automatic))
    }

    func testSavedTranslationIsReadBackForTheSameTextAndLanguage() throws {
        let store = DescriptionTranslationStore(directory: temporaryDirectory())
        try store.save(italian, of: english, from: "en", into: .italian)
        XCTAssertEqual(store.translation(of: english, into: .italian), italian)
        XCTAssertNil(store.translation(of: english, into: .french))
    }

    func testChangedTextDoesNotReuseTheOldTranslation() throws {
        let store = DescriptionTranslationStore(directory: temporaryDirectory())
        try store.save(italian, of: english, from: "en", into: .italian)
        XCTAssertNil(store.translation(of: english + " Now with a new region.", into: .italian))
    }

    func testKeyDependsOnTextAndLanguage() {
        let a = DescriptionTranslationStore.key(for: english, into: .italian)
        XCTAssertEqual(a, DescriptionTranslationStore.key(for: english, into: .italian))
        XCTAssertNotEqual(a, DescriptionTranslationStore.key(for: english, into: .german))
        XCTAssertNotEqual(a, DescriptionTranslationStore.key(for: english + ".", into: .italian))
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
