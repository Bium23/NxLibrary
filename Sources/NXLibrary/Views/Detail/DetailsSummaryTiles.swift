import SwiftUI
import NXLibraryCore

/// The game's numbers as tiles on Selene glass: Play time, Achievements (a Steam game whose achievements read)
/// and Last played. In a row across Spotlight's page, or stacked in Details' right column (`axis: .vertical`).
/// Only the achievements tile takes focus; A or a click opens the Achievements screen.
struct DetailsSummaryTiles: View {
    @Environment(\.seleneCanvas) private var canvas

    let presentation: GameDetailPresentation
    let achievements: AchievementSummary?
    let appID: UInt32?
    let focused: Bool
    var axis: Axis = .horizontal
    let onOpen: () -> Void

    /// Spotlight's page width, and Details' column.
    static let rowWidth: CGFloat = 1700
    static let columnWidth: CGFloat = 510
    static let gap: CGFloat = 24
    static let height: CGFloat = 150
    /// The achievements tile is wider than the others.
    static let achievementsShare: CGFloat = 1.7

    var body: some View {
        switch axis {
        case .vertical:
            VStack(alignment: .leading, spacing: canvas.u(Self.gap)) {
                playTime.frame(width: canvas.u(Self.columnWidth))
                lastPlayed.frame(width: canvas.u(Self.columnWidth))
            }
        case .horizontal:
            HStack(alignment: .top, spacing: canvas.u(Self.gap)) {
                let shown = summary
                let shares = shown == nil ? 2 : 2 + Self.achievementsShare
                let unit = (Self.rowWidth - Self.gap * (shown == nil ? 1 : 2)) / shares
                playTime.frame(width: canvas.u(unit))
                if let shown, let appID {
                    achievementsTile(shown, appID: appID).frame(width: canvas.u(unit * Self.achievementsShare))
                }
                lastPlayed.frame(width: canvas.u(unit))
            }
            .frame(width: canvas.u(Self.rowWidth), alignment: .leading)
        }
    }

    /// A Steam game's summary with at least one achievement.
    private var summary: AchievementSummary? {
        guard let achievements, achievements.total > 0, appID != nil else { return nil }
        return achievements
    }

    private var playTime: some View {
        tile {
            numbers(L10n.text("PLAY TIME"), presentation.playtime,
                    second: (L10n.text("THIS WEEK"), presentation.thisWeek))
        }
    }

    private var lastPlayed: some View {
        tile {
            numbers(L10n.text("LAST PLAYED"), presentation.lastPlayed,
                    second: presentation.rank.map { (L10n.text("RANK"), $0) })
        }
    }

    private func achievementsTile(_ summary: AchievementSummary, appID: UInt32) -> some View {
        tile {
            HStack(alignment: .center, spacing: canvas.u(24)) {
                VStack(alignment: .leading, spacing: canvas.u(6)) {
                    label(L10n.text("ACHIEVEMENTS"))
                    HStack(alignment: .firstTextBaseline, spacing: canvas.u(14)) {
                        (Text("\(summary.unlocked)").foregroundColor(SeleneTheme.ink)
                         + Text("/\(summary.total)").foregroundColor(SeleneTheme.ink60))
                            .seleneFont(30, .semibold)
                            .monospacedDigit()
                        Text(L10n.format("%d%%", [summary.percentComplete]))
                            .seleneFont(15, .semibold)
                            .foregroundColor(SeleneTheme.ink82)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    AchievementProgressBar(fraction: summary.total > 0 ? Double(summary.unlocked) / Double(summary.total) : 0)
                }
                HStack(spacing: canvas.u(10)) {
                    ForEach(Array(summary.recentIcons.enumerated()), id: \.offset) { _, icon in
                        AchievementIcon(appID: appID, file: icon, size: 56, dimmed: summary.unlocked == 0)
                    }
                }
            }
        }
        .seleneRowFocus(focused, radius: canvas.u(Self.radius))
        .contentShape(RoundedRectangle(cornerRadius: canvas.u(Self.radius), style: .continuous))
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("Achievements: %d of %d", [summary.unlocked, summary.total]))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
    }

    private static let radius: CGFloat = 18

    private func tile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: canvas.u(Self.radius), style: .continuous)
        return content()
            .padding(.horizontal, canvas.u(24))
            .padding(.vertical, canvas.u(20))
            .frame(maxWidth: .infinity, minHeight: canvas.u(Self.height), maxHeight: canvas.u(Self.height), alignment: .topLeading)
            .background(shape.fill(SeleneTheme.glass))
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: max(0.5, canvas.u(1))))
    }

    private func numbers(_ title: String, _ value: String, second: (String, String)?) -> some View {
        VStack(alignment: .leading, spacing: canvas.u(6)) {
            label(title)
            Text(value)
                .seleneFont(30, .semibold)
                .foregroundColor(SeleneTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if let second {
                HStack(alignment: .firstTextBaseline, spacing: canvas.u(10)) {
                    label(second.0)
                    Text(second.1)
                        .seleneFont(15, .semibold)
                        .foregroundColor(SeleneTheme.ink82)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .seleneFont(12, .semibold)
            .foregroundColor(SeleneTheme.ink60)
            .lineLimit(1)
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
