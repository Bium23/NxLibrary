import SwiftUI
import NXLibraryCore

/// A Steam game's achievements at the top of the page's right column, above the source's panel and beside
/// About this game: "17/50" with the completion beside it, the last three unlocked icons on the right and a thin
/// bar under them, in a light, nearly transparent panel with a thin outline, the surface of the panel's buttons
/// without their dark fill (maintainer's choice, 15 Nov 2026). Focused, Selene's ring sits on the panel's edge.
/// Shown only when the game has achievements and Steam's files read. A or a click opens the Achievements screen.
struct DetailsAchievementsCard: View {
    @Environment(\.seleneCanvas) private var canvas

    let summary: AchievementSummary
    let appID: UInt32
    let focused: Bool
    let onOpen: () -> Void

    /// The column's width (`BuildSourcesPanel.narrowWidth`).
    static let width = BuildSourcesPanel.narrowWidth
    private static let radius: CGFloat = SeleneTheme.contentRadius

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: canvas.u(Self.radius), style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            DetailsBandTitle(text: L10n.text("Achievements"))
            VStack(alignment: .leading, spacing: canvas.u(16)) {
                HStack(alignment: .center, spacing: canvas.u(16)) {
                    HStack(alignment: .firstTextBaseline, spacing: canvas.u(14)) {
                        (Text("\(summary.unlocked)").foregroundColor(SeleneTheme.ink)
                         + Text("/\(summary.total)").foregroundColor(SeleneTheme.ink60))
                            .seleneFont(30, .semibold)
                            .monospacedDigit()
                        Text(L10n.format("%d%% complete", [summary.percentComplete]))
                            .seleneFont(15, .semibold)
                            .foregroundColor(SeleneTheme.ink75)
                            .monospacedDigit()
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    HStack(spacing: canvas.u(8)) {
                        ForEach(Array(summary.recentIcons.enumerated()), id: \.offset) { _, icon in
                            AchievementIcon(appID: appID, file: icon, size: 44, dimmed: summary.unlocked == 0)
                        }
                    }
                }
                AchievementProgressBar(fraction: summary.total > 0 ? Double(summary.unlocked) / Double(summary.total) : 0,
                                       height: 5, track: SeleneTheme.ink25)
            }
            .padding(.horizontal, canvas.u(18))
            .padding(.vertical, canvas.u(16))
            .frame(width: canvas.u(Self.width), alignment: .leading)
            // Nearly transparent: the art's blur shows through, lightly tinted, under the buttons' thin outline.
            .background(.ultraThinMaterial, in: shape)
            .background(shape.fill(SeleneTheme.ink.opacity(0.04)))
            .overlay(shape.strokeBorder(SeleneTheme.ink15, lineWidth: max(1, canvas.u(1))))
            .contentShape(shape)
            .seleneRowFocus(focused, radius: canvas.u(Self.radius))
            .onTapGesture(perform: onOpen)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.format("Achievements: %d of %d", [summary.unlocked, summary.total]))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onOpen() }
        }
    }
}

/// A thin completion bar in the focus colour on a faint track.
struct AchievementProgressBar: View {
    @Environment(\.seleneCanvas) private var canvas
    let fraction: Double
    /// Canvas units: the page's open block uses a finer bar than the screen.
    var height: CGFloat = 6
    var track: Color = SeleneTheme.ink15

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(SeleneTheme.focus)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: canvas.u(height))
        .accessibilityHidden(true)
    }
}
