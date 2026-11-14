import SwiftUI
import AppKit
import NXLibraryCore

/// A Steam game's head in the same Selene layout as an nxnative one: the shared
/// logo area, the Play/Options/favorite positions, the stats line and (in Collection) the genre
/// chips. Play follows `SteamPlayCoordinator`: Resume while the game runs, Cancel while
/// waiting for Steam, Try again after a failure, with a one-line note above the pills.
/// Options opens `SteamOptionsView`.
struct CatalogSteamInfo: View {
    let game: CatalogGame
    let totalPlaytime: TimeInterval
    let lastPlayed: Date?
    /// Collection shows no pills, like its nxnative column.
    var collection = false
    var focused: Int? = nil
    var onAction: (Int) -> Void = { _ in }
    var onHover: (Int) -> Void = { _ in }
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Environment(\.nxAppLocale) private var localization
    @ObservedObject private var fields = SteamPersonalizations.shared.metadata
    @ObservedObject private var picks = SteamPersonalizations.shared.artwork
    @ObservedObject private var facts = SteamGameFacts.shared
    @ObservedObject private var player = SteamPlayCoordinator.shared
    private var metadata: SteamMetadata? { facts.metadata(for: game) }
    @State private var logo: NSImage?
    @State private var logoKey = ""
    @State private var shown = true
    @State private var slid = true

    private var presentation: LibraryPresentation {
        let key = game.personalizationReference.key
        var overrides: [MetadataField: String] = [:]
        for field in MetadataField.allCases { overrides[field] = fields.value(titleID: key, field: field) }
        return LibraryPresentation(game: game, steamMetadata: metadata, overrides: overrides,
                                   totalPlaytime: totalPlaytime, lastPlayed: lastPlayed)
    }
    private var currentLogoKey: String { "\(game.id)|\(picks.revision)" }

    var body: some View {
        let presentation = presentation
        VStack(alignment: .leading, spacing: 0) {
            GameLogoArea(title: game.name, logo: logoKey == currentLogoKey ? logo : nil, collection: collection)
            if let note = playNote {
                Text(note)
                    .seleneFont(19, .semibold)
                    .foregroundColor(SeleneTheme.ink75)
                    .padding(.leading, canvas.u(collection ? 0 : 4))
                    .padding(.top, canvas.u(20))
            }
            if !collection {
                GamePrimaryActions(primaryTitle: primaryTitle,
                                   isFavorite: game.isFavorite, focused: focused,
                                   primaryEnabled: primaryEnabled,
                                   onAction: onAction, onHover: onHover)
                    .padding(.leading, canvas.u(2)).padding(.top, canvas.u(18))
            }
            SeleneStatsRow(presentation: presentation)
                .padding(.leading, canvas.u(collection ? 0 : 4)).padding(.top, canvas.u(collection ? 28 : 26))
            // Spotlight places the genres in their own block under the head, as for nxnative games.
            if collection, !presentation.genres.isEmpty {
                SpotlightGenreChips(genres: presentation.genres).padding(.top, canvas.u(20))
            }
        }
        .frame(width: collection ? nil : canvas.u(900), alignment: .leading)
        .frame(maxWidth: collection ? .infinity : nil, alignment: .topLeading)
        .opacity(shown ? 1 : 0)
        .offset(x: slid ? 0 : canvas.u(collection ? -24 : -30))
        .onAppear { reveal() }
        .onChange(of: game.id) { _ in reveal() }
        .task(id: "\(game.id)|\(localization.language.rawValue)") {
            await facts.load(game, language: localization.language)
        }
        .task(id: currentLogoKey) {
            let expected = currentLogoKey
            let request = SteamArtworkRequest(game: game, role: .logo)
            var url = request.localURL(picks: picks)
            if url == nil, let id = request.appID { url = await SteamMetadataService.shared.image(appID: id, slot: .logo) }
            guard !Task.isCancelled else { return }
            logo = url.flatMap { NSImage(contentsOf: $0) }; logoKey = expected
        }
    }

    private var phase: SteamPlayState.Phase { player.phase(of: game) }
    private var primaryEnabled: Bool {
        if case .idle = phase { return player.canPlay(game) }
        return true
    }

    private var primaryTitle: String {
        switch phase {
        case .running: return L10n.text("Resume")
        case .starting: return L10n.text("Cancel")
        case .failed: return L10n.text("Try again")
        case .idle: return player.canPlay(game) ? L10n.text("Play") : L10n.text("Unavailable")
        }
    }

    private var playNote: String? {
        switch phase {
        case .starting:
            return player.mayNeedSteam(game) ? L10n.text("Steam may need you. Check Steam, the game starts after.")
                                             : L10n.text("Waiting for Steam to start the game…")
        case .failed(.clientMissing): return L10n.text("Steam is not installed on this Mac.")
        case .failed(.handoffRejected): return L10n.text("Steam did not receive the request. Try again.")
        case .failed(.notStarted): return L10n.text("The game did not start. Check Steam, then try again.")
        case .failed(.unavailable): return L10n.text("Refresh the Steam source or check the installation in Steam.")
        case .idle: return player.canPlay(game) ? nil : L10n.text("Refresh the Steam source or check the installation in Steam.")
        case .running: return nil
        }
    }

    /// The same arrival as the nxnative head: a short hold, then fade and slide (no slide under reduce motion).
    private func reveal() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { shown = false; slid = reduceMotion }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: collection ? 0.3 : 0.45).delay(collection ? 0.12 : 0.3)) { shown = true }
            if !reduceMotion { withAnimation(SeleneTheme.cubicOut(collection ? 0.3 : 0.55).delay(collection ? 0.12 : 0.3)) { slid = true } }
        }
    }
}
