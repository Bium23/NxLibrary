import SwiftUI
import NXLibraryCore

/// The common library's Steam header. This visibility milestone opens Details;
/// the later launch/session milestone owns Play, not an engine fallback.
struct CatalogSteamInfo: View {
    let game: CatalogGame
    var focused: Int? = nil
    let onAction: (Int) -> Void
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization
    @ObservedObject private var picks = SteamPersonalizations.shared.metadata
    @State private var metadata: SteamMetadata?
    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(20)) {
            Text(game.name).seleneFont(38, .semibold).foregroundColor(SeleneTheme.ink).lineLimit(2)
            HStack(spacing: canvas.u(12)) {
                Text("Steam").seleneFont(17, .semibold)
                Text(L10n.text("Mac game", context: localization)).seleneFont(17)
            }.foregroundColor(SeleneTheme.ink60)
            if metadata != nil || picks.value(titleID: game.personalizationReference.key, field: .description) != nil || picks.value(titleID: game.personalizationReference.key, field: .genres) != nil {
                Text(picks.value(titleID: game.personalizationReference.key, field: .genres) ?? (metadata?.genres ?? []).joined(separator: " · ")).seleneFont(17).foregroundColor(SeleneTheme.ink60)
                Text(picks.value(titleID: game.personalizationReference.key, field: .description) ?? metadata?.description ?? "").seleneFont(18).foregroundColor(SeleneTheme.ink).lineLimit(3)
            }
            HStack(spacing: canvas.u(14)) {
                SelenePillButton(title: "Details", focused: focused == 0) { onAction(0) }
                SelenePillButton(title: game.isFavorite ? "Unfavorite" : "Favorite", focused: focused == 1) { onAction(1) }
                SelenePillButton(title: "Hide", focused: focused == 2) { onAction(2) }
            }
        }
        .task(id: "\(game.id)|\(localization.language.rawValue)") {
            metadata = nil
            guard let id = game.steamGame?.appID else { return }
            let result = await SteamMetadataService.shared.metadata(appID: id, language: SteamMetadata.language(localization.language))
            guard !Task.isCancelled else { return }; metadata = result
        }
        .frame(maxWidth: canvas.u(1300), alignment: .leading)
    }
}
