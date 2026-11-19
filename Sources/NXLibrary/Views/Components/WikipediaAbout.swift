import SwiftUI
import NXLibraryCore

/// About this game in the player's language, with no step from the player: when the store's text is in another
/// language (or missing), the page asks `WikipediaDescriptionService` for the game's Wikipedia introduction in the
/// app's language and shows it instead, credited. The store metadata and the player's choices stay untouched.
struct WikipediaAboutLookup: Hashable {
    let query: CriticRatingQuery
    let language: AppLanguage

    /// Nil when the store's text already reads in the app's language, or the player chose it.
    init?(presentation: GameDetailPresentation, query: CriticRatingQuery?, language: AppLanguage = L10n.context.language) {
        guard let query, WikipediaDescriptions.wanted(description: presentation.description,
                                                      descriptionLanguage: presentation.descriptionLanguage,
                                                      language: language) else { return nil }
        self.query = query
        self.language = language
    }

    /// Waits a moment so gliding across tiles asks for nothing, as the ratings do.
    func load() async -> WikipediaDescription? {
        do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return nil }
        let result = await WikipediaDescriptionService.shared.load(query, language: language)
        return Task.isCancelled ? nil : result
    }
}

/// A Wikipedia introduction, with the lookup it answers: a late answer for another game or language never shows.
struct WikipediaAbout: Equatable {
    let lookup: WikipediaAboutLookup
    let description: WikipediaDescription

    /// The answer for `lookup`, if this is it.
    func matching(_ lookup: WikipediaAboutLookup?) -> WikipediaDescription? {
        lookup == self.lookup ? description : nil
    }
}

/// The credit under a Wikipedia text: CC BY-SA asks for the source and its licence, and the link opens the page.
struct WikipediaCredit: View {
    @Environment(\.seleneCanvas) private var canvas
    let pageURL: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(pageURL)
        } label: {
            HStack(spacing: canvas.u(4)) {
                Text(L10n.text("From Wikipedia, CC BY-SA."))
                Image(systemName: "arrow.up.right")
            }
            .seleneFont(14)
            .foregroundColor(SeleneTheme.ink60)
        }
        .buttonStyle(.plain)
        .help(pageURL.absoluteString)
    }
}
