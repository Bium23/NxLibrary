import SwiftUI
import NXLibraryCore

/// A Steam game's achievements at the top of the page's right column, above the source's panel and beside
/// About this game: "17/50", the completion, a bar and the last three unlocked icons. Shown only when the game
/// has achievements and Steam's files read. It takes focus; A or a click opens the Achievements screen.
struct DetailsAchievementsCard: View {
    @Environment(\.seleneCanvas) private var canvas

    let summary: AchievementSummary
    let appID: UInt32
    let focused: Bool
    let onOpen: () -> Void

    /// The column's width (`BuildSourcesPanel.narrowWidth`).
    static let width = BuildSourcesPanel.narrowWidth
    private static let radius: CGFloat = 18

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: canvas.u(Self.radius), style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            DetailsBandTitle(text: L10n.text("Achievements"))
            VStack(alignment: .leading, spacing: canvas.u(16)) {
                HStack(alignment: .center, spacing: canvas.u(16)) {
                    VStack(alignment: .leading, spacing: canvas.u(2)) {
                        (Text("\(summary.unlocked)").foregroundColor(SeleneTheme.ink)
                         + Text("/\(summary.total)").foregroundColor(SeleneTheme.ink60))
                            .seleneFont(30, .semibold)
                            .monospacedDigit()
                        Text(L10n.format("%d%% complete", [summary.percentComplete]))
                            .seleneFont(14, .semibold)
                            .foregroundColor(SeleneTheme.ink60)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: canvas.u(10)) {
                        ForEach(Array(summary.recentIcons.enumerated()), id: \.offset) { _, icon in
                            AchievementIcon(appID: appID, file: icon, size: 56, dimmed: summary.unlocked == 0)
                        }
                    }
                }
                AchievementProgressBar(fraction: summary.total > 0 ? Double(summary.unlocked) / Double(summary.total) : 0)
            }
            .padding(canvas.u(20))
            .frame(width: canvas.u(Self.width), alignment: .leading)
            .background(shape.fill(SeleneTheme.glass))
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: max(0.5, canvas.u(1))))
            .seleneRowFocus(focused, radius: canvas.u(Self.radius))
            .contentShape(shape)
            .onTapGesture(perform: onOpen)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.format("Achievements: %d of %d", [summary.unlocked, summary.total]))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onOpen() }
        }
        .shadow(color: .black.opacity(0.25), radius: canvas.u(4))
    }
}

/// A thin completion bar in the focus colour on a faint track.
struct AchievementProgressBar: View {
    @Environment(\.seleneCanvas) private var canvas
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(SeleneTheme.ink15)
                Capsule().fill(SeleneTheme.focus)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: canvas.u(6))
        .accessibilityHidden(true)
    }
}
