import SwiftUI
import NXLibraryCore

/// A Steam game's achievements at the top of the page's right column, above the source's panel and beside
/// About this game: "17/50" with the completion beside it, the last three unlocked icons on the right and a thin
/// bar under them, in a light, nearly transparent panel with a thin outline, the surface of the panel's buttons
/// without their dark fill (maintainer's choice, 15 Nov 2026). Focused, Selene's ring sits on the panel's edge.
/// Shown only when the game has achievements and Steam's files read. A or a click opens the Achievements screen;
/// under the pointer or the controller's focus it says so (maintainer's choice, 15 Nov 2026): the completion gives way
/// to "View all", the three icons fan out and brighten, and the panel lightens. Details, not a button, does none of it.
/// With Reduce motion the text and light change without movement.
struct DetailsAchievementsCard: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @State private var hovered = false

    private var active: Bool { hovered || focused }
    private var fanned: Bool { active && !reduceMotion }
    /// Slow and soft, and never past its target: a spring overshot, and quick Up/Down presses added up its
    /// speed until the icons left the panel. Interrupted, a curve only blends towards the new end.
    private var reveal: Animation { reduceMotion ? SeleneTheme.quick : .timingCurve(0.22, 1, 0.36, 1, duration: 0.45) }

    let summary: AchievementSummary
    let appID: UInt32
    let focused: Bool
    let onOpen: () -> Void

    /// The column's width (`DetailsPanel.narrowWidth`).
    static let width = DetailsPanel.narrowWidth
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
                        ZStack(alignment: .leading) {
                            Text(L10n.format("%d%% complete", [summary.percentComplete]))
                                .foregroundColor(SeleneTheme.ink75)
                                .monospacedDigit()
                                .opacity(active ? 0 : 1)
                                .offset(y: fanned ? -canvas.u(5) : 0)
                            Text(L10n.text("View all"))
                                .foregroundColor(SeleneTheme.ink)
                                .opacity(active ? 1 : 0)
                                .offset(y: active || reduceMotion ? 0 : canvas.u(5))
                        }
                        .seleneFont(15, .semibold)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    icons
                }
                AchievementProgressBar(fraction: summary.total > 0 ? Double(summary.unlocked) / Double(summary.total) : 0,
                                       height: 5, track: SeleneTheme.ink25)
            }
            .padding(.horizontal, canvas.u(18))
            .padding(.vertical, canvas.u(16))
            .frame(width: canvas.u(Self.width), alignment: .leading)
            // Nearly transparent: the art's blur shows through, lightly tinted, under the buttons' thin outline.
            .background(.ultraThinMaterial, in: shape)
            .background(shape.fill(SeleneTheme.ink.opacity(active ? 0.08 : 0.04)))
            .overlay(shape.strokeBorder(active ? SeleneTheme.ink25 : SeleneTheme.ink15, lineWidth: max(1, canvas.u(1))))
            .contentShape(shape)
            .onHover { hovered = $0 }
            .animation(reveal, value: active)
            .seleneRowFocus(focused, radius: canvas.u(Self.radius))
            .onTapGesture(perform: onOpen)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.format("Achievements: %d of %d", [summary.unlocked, summary.total]))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onOpen() }
        }
    }
}

extension DetailsAchievementsCard {
    /// The last three unlocked icons. Active, they fan out like a held hand of cards: the outer ones tilt
    /// and drop a little, the gaps open, and all three brighten.
    private var icons: some View {
        let count = summary.recentIcons.count
        let middle = Double(max(count - 1, 0)) / 2
        return HStack(spacing: canvas.u(fanned ? 12 : 8)) {
            ForEach(Array(summary.recentIcons.enumerated()), id: \.offset) { index, icon in
                let side = Double(index) - middle
                AchievementIcon(appID: appID, file: icon, size: 44, dimmed: summary.unlocked == 0)
                    .opacity(active ? 1 : 0.88)
                    .scaleEffect(fanned ? 1.04 : 1)
                    .rotationEffect(.degrees(fanned ? side * 5 : 0), anchor: .bottom)
                    .offset(y: fanned ? canvas.u(CGFloat(abs(side)) * 2) : 0)
                    .zIndex(-abs(side))
            }
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
