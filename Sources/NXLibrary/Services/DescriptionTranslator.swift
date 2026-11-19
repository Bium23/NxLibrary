import SwiftUI
import Translation
import NXLibraryCore

/// Translate in About this game: Apple's Translation, on this Mac, only when the player asks.
/// It covers every description alike (store text, database pick, the player's own) because it reads the
/// language of the text itself. One text at a time; the result is kept in `DescriptionTranslationStore`,
/// keyed by the exact text, so a changed description is offered again and never shows an old translation.
/// Translation needs macOS 15; earlier systems never see the button.
@MainActor
final class DescriptionTranslator: ObservableObject {
    static let shared = DescriptionTranslator()

    enum Phase: Equatable {
        /// No button: the text is already in the app's language, too short to tell, or the Mac has no Translation.
        case none
        case offer
        case translating
        case translated(String)
        /// Translated before; the player chose to read the original.
        case original(String)
        case failed
    }

    struct Request: Equatable {
        let id: Int
        let text: String
        let source: String
        let target: AppLanguage
    }

    @Published private(set) var revision = 0
    /// What the host's `translationTask` runs next.
    @Published private(set) var request: Request?

    private let store = DescriptionTranslationStore()
    private var sources: [String: String?] = [:]
    private var translations: [String: String?] = [:]
    private var showingOriginal: Set<String> = []
    private var failed: Set<String> = []
    private var translatingKey: String?
    private var nextID = 0

    static var isAvailable: Bool {
        if #available(macOS 15, *) { return true }
        return false
    }

    func phase(for text: String, language: AppLanguage = L10n.context.language) -> Phase {
        guard Self.isAvailable, source(of: text, into: language) != nil else { return .none }
        let key = DescriptionTranslationStore.key(for: text, into: language)
        if let translation = translation(of: text, key: key, into: language) {
            return showingOriginal.contains(key) ? .original(translation) : .translated(translation)
        }
        if translatingKey == key { return .translating }
        return failed.contains(key) ? .failed : .offer
    }

    /// The text About this game shows: the translation once asked for, otherwise the original.
    func displayed(_ text: String, language: AppLanguage = L10n.context.language) -> String {
        if case .translated(let translation) = phase(for: text, language: language) { return translation }
        return text
    }

    /// Translate, Show original, Show translation: the one action of the button and of X.
    func toggle(_ text: String, language: AppLanguage = L10n.context.language) {
        let key = DescriptionTranslationStore.key(for: text, into: language)
        switch phase(for: text, language: language) {
        case .none, .translating: return
        case .translated: showingOriginal.insert(key)
        case .original: showingOriginal.remove(key)
        case .offer, .failed:
            guard let source = source(of: text, into: language) else { return }
            failed.remove(key)
            translatingKey = key
            nextID += 1
            request = Request(id: nextID, text: text, source: source, target: language)
        }
        revision += 1
    }

    @available(macOS 15, *)
    func run(_ session: TranslationSession) async {
        guard let request else { return }
        let key = DescriptionTranslationStore.key(for: request.text, into: request.target)
        do {
            let response = try await session.translate(request.text)
            let translation = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translation.isEmpty else { throw CocoaError(.featureUnsupported) }
            try? store.save(translation, of: request.text, from: request.source, into: request.target)
            translations[key] = translation
            showingOriginal.remove(key)
        } catch is CancellationError {
            // Replaced by a newer request: Translate stays on offer, with no notice.
        } catch {
            // Declined download or unsupported pair: a notice, and Translate tries again; nothing is saved.
            failed.insert(key)
        }
        if translatingKey == key { translatingKey = nil }
        if self.request?.id == request.id { self.request = nil }
        revision += 1
    }

    private func source(of text: String, into language: AppLanguage) -> String? {
        let key = DescriptionTranslationStore.key(for: text, into: language)
        if let known = sources[key] { return known }
        let source = TextLanguage.translationSource(for: text, into: language)
        sources[key] = source
        return source
    }

    private func translation(of text: String, key: String, into language: AppLanguage) -> String? {
        if let known = translations[key] { return known }
        let saved = store.translation(of: text, into: language)
        translations[key] = saved
        return saved
    }
}

/// Runs the translator's requests in the window, where Translation can ask to download a language.
@available(macOS 15, *)
private struct DescriptionTranslationHost: ViewModifier {
    @ObservedObject var translator: DescriptionTranslator
    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .onChange(of: translator.request) {
                guard let request = translator.request else { return }
                let next = TranslationSession.Configuration(source: Locale.Language(identifier: request.source),
                                                            target: Locale.Language(identifier: request.target.rawValue))
                if configuration == next { configuration?.invalidate() } else { configuration = next }
            }
            .translationTask(configuration) { session in
                await translator.run(session)
            }
    }
}

extension View {
    /// Placed once at the window's root.
    @ViewBuilder func descriptionTranslationHost() -> some View {
        if #available(macOS 15, *) {
            modifier(DescriptionTranslationHost(translator: .shared))
        } else {
            self
        }
    }
}

/// The line above a description: the language note, then Translate / Show original, or what is happening.
struct DescriptionTranslateLine: View {
    @Environment(\.seleneCanvas) private var canvas
    @ObservedObject private var translator = DescriptionTranslator.shared
    let text: String
    let note: String?
    var focused = false
    /// Space below the line, in canvas units, only when the line is drawn.
    var bottomPadding: CGFloat = 0

    var body: some View {
        let phase = translator.phase(for: text)
        let status = Self.status(phase, note: note)
        if status != nil || phase != .none {
            HStack(spacing: canvas.u(12)) {
                if let status {
                    Text(status).seleneFont(14).foregroundColor(SeleneTheme.ink60)
                }
                if let title = Self.buttonTitle(phase) {
                    Button(title) { translator.toggle(text) }
                        .buttonStyle(.plain)
                        .seleneFont(14, .semibold)
                        .foregroundColor(SeleneTheme.glyph)
                        .padding(.horizontal, canvas.u(10))
                        .padding(.vertical, canvas.u(3))
                        .seleneRowFocus(focused, radius: canvas.u(12))
                }
            }
            .padding(.bottom, canvas.u(bottomPadding))
        }
    }

    static func status(_ phase: DescriptionTranslator.Phase, note: String?) -> String? {
        switch phase {
        case .translating: return L10n.text("Translating on this Mac…")
        case .translated: return L10n.text("Translated on this Mac.")
        case .failed: return L10n.text("Translation is not available on this Mac right now.")
        case .none, .offer, .original: return note
        }
    }

    static func buttonTitle(_ phase: DescriptionTranslator.Phase) -> String? {
        switch phase {
        case .offer, .failed: return L10n.text("Translate")
        case .translated: return L10n.text("Show original")
        case .original: return L10n.text("Show translation")
        case .none, .translating: return nil
        }
    }
}
