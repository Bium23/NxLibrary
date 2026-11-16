import SwiftUI
import NXLibraryCore

/// A read-only value in Details, not a new card or a personal-vote control.
struct CriticRatingValue: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization
    let result: CriticRatingResult?

    var body: some View {
        Group {
            if let rating = result?.rating {
                HStack(alignment: .center, spacing: canvas.u(8)) {
                    HStack(spacing: canvas.u(2)) {
                        ForEach(Array(rating.starFills.enumerated()), id: \.offset) { _, fill in
                            Image(systemName: "star.fill")
                                .foregroundColor(SeleneTheme.ink.opacity(0.18))
                                .overlay(alignment: .leading) {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(SeleneTheme.ink90)
                                        .mask(alignment: .leading) {
                                            GeometryReader { geometry in
                                                Rectangle().frame(width: geometry.size.width * fill)
                                            }
                                        }
                                }
                        }
                    }
                    .font(.system(size: canvas.u(13), weight: .regular))
                    .fixedSize()
                    .accessibilityHidden(true)
                    Text(rating.number(locale: localization.formatLocale))
                        .seleneFont(15, .semibold)
                        .foregroundColor(SeleneTheme.ink90)
                        .monospacedDigit()
                        .fixedSize()
                    Text(rating.attribution(context: localization))
                        .seleneFont(11)
                        .foregroundColor(SeleneTheme.ink60)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .help(provenance(rating))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(provenance(rating))
            } else {
                Text(result == nil ? L10n.text("Loading…") : L10n.text("Rating unavailable"))
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink60)
            }
        }
    }

    private func provenance(_ rating: CriticRating) -> String {
        var lines = [L10n.text(rating.labelKey), rating.number(locale: localization.formatLocale),
                     rating.attribution(context: localization),
                     rating.platforms.isEmpty ? L10n.text("Platform not specified")
                        : (rating.platforms.contains("Q14116") ? "macOS"
                           : (rating.platforms.contains("Q122761124") ? "Nintendo Switch 2" : "Nintendo Switch"))]
        if let count = rating.reviewCount {
            lines.append(L10n.format(rating.isCommunity ? "User ratings: %d" : "Critic reviews: %d", [count]))
        }
        if let date = rating.scoreDate { lines.append(String(date.dropFirst(date.hasPrefix("+") ? 1 : 0).prefix(10))) }
        if result?.isStale == true { lines.append(L10n.text("Saved rating · refresh unavailable")) }
        lines.append(rating.sourceURL.absoluteString)
        return lines.joined(separator: " · ")
    }
}
