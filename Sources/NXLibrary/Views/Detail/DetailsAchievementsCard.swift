import SwiftUI
import NXLibraryCore

/// A Steam game's achievements at the top of the page's right column, above the source's panel and beside
/// About this game: "17/50" with the completion beside it, the last three unlocked icons on the right and a thin
/// bar under them. Open on the art like About and Installation, with no box of its own (maintainer's choice,
/// 15 Nov 2026); focused, Selene's ring frames it a little outside its text, as it frames a screenshot. Shown
/// only when the game has achievements and Steam's files read. A or a click opens the Achievements screen.
struct DetailsAchievementsCard: View {
    @Environment(\.seleneCanvas) private var canvas

    let summary: AchievementSummary
    let appID: UInt32
    let focused: Bool
    let onOpen: () -> Void

    /// The column's width (`BuildSourcesPanel.narrowWidth`).
    static let width = BuildSourcesPanel.narrowWidth
    /// How far the focus ring sits outside the content, so the text stays aligned with the column.
    private static let ringMargin: CGFloat = 16
    private static let radius: CGFloat = 16

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
                            .seleneFont(15, .medium)
                            .foregroundColor(SeleneTheme.ink60)
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
                                       height: 4)
            }
            .frame(width: canvas.u(Self.width), alignment: .leading)
            .padding(canvas.u(Self.ringMargin))
            .contentShape(shape)
            .seleneRowFocus(focused, radius: canvas.u(Self.radius))
            .padding(-canvas.u(Self.ringMargin))
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

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(SeleneTheme.ink15)
                Capsule().fill(SeleneTheme.focus)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: canvas.u(height))
        .accessibilityHidden(true)
    }
}
