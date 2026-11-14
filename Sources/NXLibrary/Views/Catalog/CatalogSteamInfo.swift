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
    @ObservedObject private var logos = SteamLogoCache.shared
    private var metadata: SteamMetadata? { facts.metadata(for: game) }
    @State private var shown = true
    @State private var restShown = true
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
            // Spotlight moves only the logo and fades the rest in after it; Collection moves the whole column
            // (`SpotlightGameInfoView`, `CollectionInfoView`).
            GameLogoArea(title: game.name, logo: logos.logo(for: currentLogoKey), collection: collection)
                .offset(x: collection || slid ? 0 : canvas.u(SpotlightGameInfoView.logoSlideDistance))
                .opacity(collection || shown ? 1 : 0)
            rest(presentation)
                .opacity(collection || restShown ? 1 : 0)
        }
        .frame(width: collection ? nil : canvas.u(900), alignment: .leading)
        .frame(maxWidth: collection ? .infinity : nil, alignment: .topLeading)
        .opacity(!collection || shown ? 1 : 0)
        .offset(x: !collection || slid ? 0 : canvas.u(CollectionInfoView.slideDistance))
        .onAppear { reveal() }
        .onChange(of: game.id) { _ in reveal() }
        .task(id: "\(game.id)|\(localization.language.rawValue)") {
            await facts.load(game, language: localization.language)
        }
        .task(id: currentLogoKey) {
            await logos.load(game, key: currentLogoKey, picks: picks)
        }
    }

    @ViewBuilder
    private func rest(_ presentation: LibraryPresentation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
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

    /// The nxnative head's arrival, motion for motion: in Spotlight the logo holds, then fades and slides while
    /// the pills and stats fade in after it; in Collection the whole column fades and slides. Reduce motion
    /// keeps the fades and drops the slides.
    private func reveal() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { shown = false; restShown = false; slid = reduceMotion }
        DispatchQueue.main.async {
            if collection {
                withAnimation(CollectionInfoView.fade) { shown = true; restShown = true }
                if !reduceMotion { withAnimation(CollectionInfoView.slide) { slid = true } }
            } else {
                withAnimation(SpotlightGameInfoView.logoFade) { shown = true }
                withAnimation(SpotlightGameInfoView.restMotion) { restShown = true }
                if !reduceMotion { withAnimation(SpotlightGameInfoView.logoSlide) { slid = true } }
            }
        }
    }
}

/// Decoded Steam logos, kept like nxnative ones (`GameArtLoader`): a game seen before shows its logo from the
/// first frame of its arrival, and a logo that lands later fades in over its title.
@MainActor
final class SteamLogoCache: ObservableObject {
    static let shared = SteamLogoCache()
    private let logos = NSCache<NSString, NSImage>()
    /// Bumped (animated) when a logo lands, so heads reading it redraw.
    @Published private var tick = 0

    func logo(for key: String) -> NSImage? {
        _ = tick
        return logos.object(forKey: key as NSString)
    }

    /// `key` names the game and the player's picks revision, so a new pick loads again.
    func load(_ game: CatalogGame, key: String, picks: SteamPersonalizationStore) async {
        guard logos.object(forKey: key as NSString) == nil else { return }
        let request = SteamArtworkRequest(game: game, role: .logo)
        var url = request.localURL(picks: picks)
        if url == nil, let id = request.appID { url = await SteamMetadataService.shared.image(appID: id, slot: .logo) }
        guard !Task.isCancelled, let url else { return }
        // Decoded off the main thread like an nxnative logo: a lazily decoded file cost the frame that drew it.
        let image = await GameArtLoader.decodeLogo(at: url)
        guard !Task.isCancelled, let image else { return }
        logos.setObject(image, forKey: key as NSString)
        withAnimation(.easeOut(duration: 0.3)) { tick += 1 }
    }
}
